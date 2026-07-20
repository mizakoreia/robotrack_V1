## Context

O legado é um PWA vanilla sobre Firestore. Todo o domínio do RoboTrack mora em poucos
documentos gigantes: o documento do workspace carrega `defaultTasks` e `responsibles`; o
documento de projeto carrega `cells[] → robots[] → tasks[] → history[]`. Não há junção,
não há FK, não há constraint. O que existe são **cinco camadas de código de leitura
tolerante** acumuladas em cima do dado (§1.4 itens 1/2/3 + as duas migrações de §4.4),
que consertavam o dado preguiçosamente, no cliente, na hora de exibir.

O alvo é Postgres com RLS (D2), PK uuid gerável no cliente (D1/D13), `people.id` como
identidade estável (D10) e o sentinela `"Não Atribuído"` abolido (D11). Nada disso
tolera "dado meio migrado". Ou o registro entra íntegro, ou não entra.

Portanto o trabalho não é "copiar JSON para tabelas". É: **transformar cinco regras de
leitura em cinco regras de escrita, uma vez só, com prova de que o resultado é
equivalente.**

Restrição operacional dominante: **não temos o export em mãos.** `RoboTrack_Database.json`
não está no repositório nem em nenhum caminho conhecido. Isso divide o trabalho em
"planejável e codificável contra fixture sintética" e "só executável quando o arquivo
chegar". O design abaixo assume que essa divisão é permanente e explícita, não um
detalhe a resolver depois.

## Goals / Non-Goals

**Goals**

1. Rodar o importador duas vezes sobre o mesmo arquivo produz **zero** registros novos e
   **zero** campos alterados na segunda vez.
2. As três regras de §1.4 produzem exatamente o mesmo resultado observável que o legado
   produzia na leitura — mas materializado no banco.
3. Nenhuma `Person` chamada `"Não Atribuído"` é criada, em nenhuma circunstância, mesmo
   por um bug futuro do importador.
4. Nenhum dado malformado aborta o run inteiro; ele vai para quarentena com o caminho
   legado que o originou.
5. ≥20 robôs de amostra têm progresso ponderado (§2.1) idêntico entre origem e destino.
6. Existe um caminho de volta que não depende de `pg_restore` do banco inteiro.

**Non-Goals**

- Zero-downtime. O corte é uma janela de manutenção.
- Reversibilidade da direção contrária (exportar do relacional para Firestore).
- Importar histórico de autenticação, sessões ou tokens.
- Performance além de "cabe numa janela de manutenção". O dataset legado é da ordem de
  dezenas de projetos, não milhões de linhas.

## Decisions

### D-LDM-1 — §4.4 vira pré-processador offline, não migração em runtime (decisão declarada)

O legado executava as duas migrações estruturais **na primeira leitura que detectasse
formato antigo, só pelo dono, numa operação atômica que também removia os campos
antigos**. O plano anterior detectava o formato e nunca implementava nenhuma das três
propriedades — nem dizia que estava trocando o mecanismo. Aqui trocamos, e declaramos:

`rake legacy:normalize[input.json,output.json]` lê o export bruto e emite o export
**canônico** (v1). As três propriedades do legado são preservadas assim:

| Propriedade legada | Como sobrevive no porte |
|---|---|
| "uma única vez" | O arquivo canônico é o artefato. Rodar `normalize` de novo sobre um arquivo **já** canônico é no-op detectado por `schemaVersion: 1` no topo. Não existe estado mutável para migrar duas vezes. |
| "só pelo dono" | Deixa de ser uma checagem de autorização em runtime e vira **procedência do arquivo**: o export só pode ter sido produzido pelo dono (o exportador de §3.11 é restrito ao dono, `workspace-settings`). O rake registra `ownerUid` do arquivo em `legacy_import_runs.legacy_owner_uid` e **recusa** importar se o workspace de destino tiver dono diferente. |
| "atômica, removendo os campos antigos" | O `normalize` é uma transformação pura arquivo→arquivo: ou emite o arquivo completo, ou não emite arquivo nenhum. Os campos antigos (`workspace.projects`, `workspace.logs`) **não são copiados** para o canônico. Não há estado parcial possível. |

**Alternativa descartada:** reimplementar a migração como código de runtime no Rails
(detectar formato antigo numa leitura e migrar). Rejeitada porque no relacional não há
"formato antigo" a detectar — o schema é fixo. Reproduzir o gatilho preguiçoso exigiria
inventar uma coluna de estado de migração no workspace, ou seja, inventar a doença para
poder aplicar o remédio.

**Alternativa descartada:** rodar `normalize` dentro do `import` como um passo interno,
sem artefato intermediário. Rejeitada porque perde a auditabilidade: com o arquivo
canônico em disco, a validação por amostragem (D-LDM-5) tem um alvo estável para
comparar, e um segundo run compara byte a byte.

### D-LDM-2 — Idempotência é estrutural (UUIDv5 derivado do caminho legado), não uma consulta

**Onde a invariante mora: na PRIMARY KEY.** Cada registro importado recebe
`id = uuidv5(namespace_robotrack, caminho_legado_canônico)`, onde o caminho é uma string
determinística, por exemplo:

```
ws:<legacyWsId>/proj:<legacyProjId>/cell:<idx-ou-legacyId>/robot:<...>/task:<...>
advance:<...>#<índice na lista history>
person:<legacyWsId>:<lower(nome)>
```

Toda escrita é `INSERT … ON CONFLICT (id) DO NOTHING`. Consequência: a segunda execução
colide na PK e não insere nada, sem uma única consulta de existência, sem transação longa
de leitura-antes-de-escrever, e **sem corrida** entre dois runs concorrentes.

Casos onde o legado não tem id (célula e robô são posições em array): o caminho usa o
**índice na lista**. Isso é aceitável porque o arquivo canônico é imutável — o índice não
muda entre runs do mesmo arquivo. Está explicitamente documentado que **reordenar o
array no legado e reexportar produz ids diferentes**; por isso o import é big-bang único
(Não-objetivo de sincronização contínua).

`legacy_id_map (run_id, legacy_path, entity_type, new_id)` é gravada em paralelo. Ela não
é usada para idempotência (a PK é); serve para diagnóstico, para o rollback por run
(D-LDM-6) e para o relatório de validação.

**Alternativa descartada:** idempotência por "procurar por nome + pai antes de inserir".
Rejeitada por três razões: é O(n) consultas, não é atômica entre runs concorrentes, e
quebra no exato caso que mais importa — dois robôs homônimos na mesma célula, que o
legado permite e a busca por nome fundiria em um.

**Alternativa descartada:** `ON CONFLICT DO UPDATE` (upsert). Rejeitada porque um segundo
run passaria a **sobrescrever** edições feitas no sistema novo depois do corte. O
requisito é "zero registros novos", e o requisito implícito é "zero dano". `DO NOTHING`
entrega os dois.

### D-LDM-3 — O sentinela morre em três camadas, não numa

D11 diz que `"Não Atribuído"` é abolido. A armadilha concreta: o passo "resolver nomes de
responsáveis para `Person`" é o mesmo código para todos os nomes, e `"Não Atribuído"` é
só mais uma string na lista `assignees` ou no campo `resp`. Um resolver ingênuo cria a
pessoa.

Três camadas, de fora para dentro:

1. **Normalização (arquivo canônico):** `normalize` remove `"Não Atribuído"` de
   `workspace.responsibles` e de qualquer `assignees`, e apaga `resp` quando igual ao
   sentinela. O arquivo canônico não contém a string em posição de nome de pessoa.
2. **Resolver (`Legacy::AssigneeResolver`):** ponto **único** de conversão nome →
   `people.id`. Ele é a única chamada permitida a `Person.create`; qualquer outro serviço
   de import recebe ids já resolvidos. A comparação é case-insensitive e com trim
   (`"não atribuído"`, `" Não Atribuído "` também são filtrados).
3. **Banco (a que importa):** `CHECK (btrim(lower(name)) <> 'não atribuído')` em
   `people`, mais índice único `(workspace_id, lower(btrim(name)))`. **Um model se
   contorna por `rails console`; uma CHECK não.** Se um bug futuro do importador tentar,
   o run falha alto em vez de poluir o workspace silenciosamente.

O índice único também resolve a deduplicação de homônimos: `"João Silva"` e
`"joão silva"` no mesmo workspace legado colapsam numa `Person`, que é o comportamento
correto (D10: identidade estável). Nomes que colidem só por acento (`"Joao"` vs `"João"`)
**não** colapsam — considerá-los iguais exigiria `unaccent` e destruiria pessoas
legitimamente distintas. Isso vai para o relatório do run como aviso, não como erro.

**Alternativa descartada:** importar `"Não Atribuído"` como uma `Person` marcada
`sentinel: true` e filtrá-la nas consultas. Rejeitada — é exatamente o defeito que D11
elimina, com uma camada de esparadrapo por cima.

### D-LDM-4 — As três regras de §1.4, uma a uma, com a precedência escrita

**Item 1 — responsáveis.** A cascata é, em ordem, no importador de tarefa:

```
se task["assignees"] é Array          → usa a lista (mesmo vazia; lista vazia PARA a cascata)
senão se task["resp"] é String presente e ≠ sentinela → usa [resp]
senão                                  → []
```
O detalhe que o plano anterior perderia: **`assignees: []` é uma resposta, não uma
ausência.** Se a tarefa tem `assignees: []` e `resp: "Maria"`, o resultado é **vazio** —
porque no legado `assignees` existir já vencia `resp`. Cair para `resp` nesse caso
ressuscitaria responsáveis que o usuário removeu.
Os nomes resultantes passam pelo `AssigneeResolver` (D-LDM-3) e viram linhas de
`task_assignees` por `person_id` (`robot-tasks`). **`resp` nunca é gravado** — a coluna
não existe (D-RT-2 de `robot-tasks`).

**Item 2 — nota livre → histórico.** Condição: `obs` presente e não vazio **e** `history`
vazio ou ausente. Resultado: uma linha de `task_advances` no contrato `legacy` que
`progress-advances` nos entregou (proposal deles, "Avisos a outras capacidades"):
`by = NULL`, `author_name_snapshot = "(nota anterior)"`, `from_progress = 0`,
`to_progress = 0`, `comment = obs`, `legacy = true`, isenta da CHECK de comentário.
`recorded_at` (D8) recebe o `_updatedAt` da tarefa ou do projeto; se ambos ausentes,
recebe o `exportedAt` do arquivo — **nunca `Time.now`**, que tornaria o run não
determinístico e quebraria a idempotência do UUIDv5 do avanço.
Se `obs` está preenchido **e** `history` tem entradas, `obs` é descartado e registrado em
quarentena — o legado nesse caso também não convertia (a condição era `history` vazio), e
inventar uma entrada mudaria a ordem da trilha.
Consequência a jusante já aceita por `robot-task-table`: o aviso "trilha faltando" passa a
ser `0 < progress < 100 AND advances_count = 0`, porque a nota legada já é trilha.

**Item 3 — filtro de aplicação.** `appFilters` e `apps` são ambos aceitos na leitura do
template. Precedência: se **os dois** existirem, vence `appFilters` (o nome novo) e a
divergência vai para o relatório; se só `apps` existir, é lido como `app_filters`. O
valor `"Todas"` do legado é **preservado como está** — `task-catalog` já declarou que a
predicate trata `"Todas"` e tem teste para isso (design D-TC-5 / linha de risco deles).
Normalizar `"Todas"` para lista vazia seria semanticamente equivalente hoje, mas
destruiria a informação de que o usuário escolheu explicitamente.

**Normalização defensiva.** Toda descida de nível usa `Array(hash["cells"])`,
`Array(hash["robots"])`, `Array(hash["tasks"])`, `Array(task["history"])`. Projeto sem
`cells`, célula sem `robots`, robô sem `tasks` importam como pai válido com zero filhos.
Isso é o mesmo requisito que `commissioning-hierarchy` já implementou na leitura da API —
aqui é na leitura do **arquivo**, e é independente.

### D-LDM-5 — A validação compara contra o export, não contra o sistema legado vivo

O plano anterior exigia "comparar ≥20 robôs entre o sistema antigo e o novo" sem nunca
providenciar que o sistema antigo continuasse executável: seria preciso manter o PWA
servido, um projeto Firebase ativo, credenciais, e um snapshot congelado do Firestore no
mesmo instante do export — senão a comparação mede drift, não migração.

Decisão: **o oráculo é o arquivo canônico.** `Legacy::SampleValidator` reimplementa §2.1
(média ponderada por peso, ignorando `N/A`; robô sem tarefas = 0; robô só com `N/A` = 100)
em Ruby puro **a partir do JSON**, sem tocar em ActiveRecord, e compara com o
`progress_cache` do robô importado (D5, `progress-rollup`). Amostra: ≥20 robôs, escolhida
de forma **determinística e adversarial**, não aleatória — obrigatoriamente incluindo
robô sem tarefas, robô só com `N/A`, robô com pesos diferentes de 1, robô com tarefa em
progresso parcial, e robô com o maior número de tarefas do arquivo. Diferença tolerada:
zero.

Isso é **mais forte** do que comparar com o sistema vivo, porque o sistema vivo calcula
com o mesmo código de origem em ambos os lados de uma tela e não prova nada sobre a
tradução. Uma reimplementação independente do cálculo prova.

**Alternativa descartada:** manter o legado no ar. Rejeitada por custo e por medir a
coisa errada. Se o negócio exigir, é um pré-requisito de infra explícito e um projeto
próprio — não uma linha de checklist nossa.

**Alternativa descartada:** comparar contra a API nova em vez de contra o banco.
Rejeitada porque a API aplica RLS, paginação e entities; um mismatch não distinguiria erro
de import de erro de apresentação.

### D-LDM-6 — Backup em duas granularidades, rollback por run

Antes de qualquer escrita: `pg_dump -Fc` do banco em `LEGACY_IMPORT_BACKUP_DIR`, com o
caminho gravado em `legacy_import_runs.backup_path`. O run **recusa iniciar** se o dump
falhar ou se o diretório não for gravável. Essa é a rede de segurança grossa.

A rede fina é `rake legacy:rollback[run_id]`: usa `legacy_id_map` para apagar, em ordem
inversa de dependência, exatamente as linhas que aquele run criou — e **só** elas.
Registros criados por usuários depois do corte não são tocados. Restrição importante:
o rollback **não** apaga `audit_logs` (D12: `REVOKE UPDATE, DELETE`); ele grava no log
que o rollback ocorreu. As entradas de auditoria importadas ficam. É uma inconsistência
deliberada e documentada: auditoria imutável vale mais que rollback perfeito.

**Alternativa descartada:** rodar o import inteiro numa única transação e usar `ROLLBACK`.
Rejeitada porque, com quarentena e relatório, queremos que um run parcialmente bem
sucedido **persista** o que deu certo e reporte o que não deu; e porque uma transação
única sobre o dataset inteiro bloqueia RLS e vacuum durante toda a janela.

### D-LDM-7 — Registro irreparável vai para quarentena, constraint não é relaxada

Casos reais esperados: `status` fora do enum de §1.1; `progress` fora de 0–100;
`application` do robô fora do enum de §1.2; `weight` não numérico ou ≤ 0; entrada de
`history` com `to` ausente. Para cada um: o registro **não** entra, uma linha vai para o
relatório do run com `legacy_path` + campo + valor bruto + motivo, e o run continua.

O que nunca acontece: afrouxar CHECK, criar valor de enum novo, ou "melhor esforço"
convertendo `progress: 150` para `100`. Um dado que o esquema novo considera inválido é
uma decisão de negócio, não um detalhe de parsing.

Exceção com regra definida (porque é frequente demais para virar quarentena): status e
progresso **incoerentes entre si** (`status: "Concluído"` com `progress: 80`). A CHECK de
coerência de `progress-advances` os rejeitaria. Regra: **`progress` é a fonte de
verdade** e `status` é derivado dele pela máquina de estados de §2.2, com a divergência
registrada no relatório. Motivo: `progress` é o número que o cálculo de §2.1 usa e que a
validação por amostragem confere; `status` é rótulo.

### D-LDM-8 — O formato do arquivo é um contrato de duas pontas, versionado

`config/legacy_export_v1.schema.json` (JSON Schema) define o export canônico, com
`schemaVersion` obrigatório no topo. Nós **validamos contra ele** antes de importar (falha
rápida com o caminho do campo ofensor, em vez de `NoMethodError` no meio do run) e
`workspace-settings` **emite** contra ele em §3.11. O schema mora neste repo, não no
legado, porque o legado não vai receber mais commits.

O export bruto do Firestore (pré-`normalize`) **não** é validado pelo schema — ele é, por
definição, o formato antigo que §4.4 conserta. Só o canônico é.

## Riscos / Trade-offs

| Risco | Impacto | Mitigação |
|---|---|---|
| **O export não existe.** Não está no repo nem em caminho conhecido. | Metade das tarefas não é executável | Explicitado em `tasks.md` com `[BLOQUEADO: export]`. As tarefas de código rodam contra fixture sintética escrita à mão a partir de §1.1, que exercita todos os casos de §1.4 e de D-LDM-7. |
| Célula/robô sem id no legado → id derivado do índice do array | Reexportar depois de reordenar produz ids diferentes | Big-bang único, documentado. O run grava o hash SHA-256 do arquivo canônico em `legacy_import_runs`; importar um arquivo com hash diferente para um workspace já importado exige `--force` e emite aviso. |
| `AssigneeResolver` colapsa homônimos por `lower()` | Duas pessoas reais viram uma | Aceito e declarado: é a semântica de D10 (identidade por nome é o único sinal que o legado tem). Colisões só por acento **não** colapsam e vão para o relatório para revisão humana. |
| `recorded_at` derivado de `_updatedAt` do projeto quando a tarefa não tem | Trilha legada com timestamp impreciso | A entrada é marcada `legacy: true`; a UI de `robot-task-table` já distingue. O determinismo importa mais que a precisão de um dado que o legado nunca teve. |
| Volume desconhecido | Janela de manutenção mal dimensionada | Tarefa de dry-run que só conta e reporta, sem escrever, antes do run real. `LEGACY_IMPORT_BATCH_SIZE` ajustável. |
| RLS bloqueia a escrita do importador | Run falha em massa | O rake seta `app.current_workspace_id` por workspace explicitamente (D2). Teste que roda o importador com a variável **não** setada e exige falha limpa, não escrita em workspace errado. |
| `audit_logs` importados não são removíveis pelo rollback (D12) | Rollback é parcial | Declarado. As entradas importadas carregam marcação de origem legada na mensagem, então um segundo import não é confundido com atividade real. |

## Plano de migração

1. `workspace-settings` congela o schema v1 junto conosco (D-LDM-8).
2. Fixture sintética + suíte verde, sem o export real.
3. **[bloqueado no export]** Recebe o arquivo. `rake legacy:normalize` → canônico.
   Validação de schema. Dry-run contando entidades e listando quarentena prevista.
4. Janela de manutenção: `pg_dump` → `rake legacy:import` → relatório.
5. `rake legacy:validate_sample` — ≥20 robôs, diferença zero. Se falhar: `rake
   legacy:rollback[run_id]` e volta ao passo 3.
6. Segunda execução do `import` no mesmo arquivo, em produção, como prova de
   idempotência: 0 criados.

## O que ficou de fora do `tasks.md`

A capacidade é grande (3 specs, 20 requisitos) porque o import toca oito tipos de entidade
e cinco regras de compatibilidade. Para caber no teto de tarefas, foram deliberadamente
deixadas de fora, com justificativa:

- **Paralelização / streaming do parser JSON.** O dataset legado é da ordem de dezenas de
  projetos; carregar o arquivo inteiro em memória é aceitável. Se a tarefa 8.6 revelar
  volume acima de ~200 MB, isto volta como tarefa nova.
- **Importação de convites (`invitations`).** Escopo atual importa `memberships` ativos e
  nenhum convite. Precisa de decisão conjunta com `workspace-invitations` (ver Perguntas
  em aberto).
- **UI de importação e barra de progresso.** O importador é rake, operado no corte.
- **Reconciliação pós-corte** (comparar o banco novo com o export semanas depois). O
  `file_sha256` no run já permite refazer a validação sob demanda.

## Perguntas em aberto

- **Quantos workspaces o export contém?** Se for mais de um, é um run por workspace ou um
  run global? O design assume **um run por workspace** (é assim que `legacy_owner_uid`
  e RLS funcionam), mas isso precisa ser confirmado contra o arquivo real.
- **`workspace.responsibles` tem nomes que não aparecem em nenhuma tarefa.** Importar
  como `Person` órfã (fiel ao legado, que os mostrava no modal de atribuição) ou
  descartar? Assumimos **importar** — §3.5 lista "todos os responsáveis do workspace", não
  só os atribuídos.
- **`memberships` e `invitations` legados entram neste import?** Convites expirados quase
  certamente não. Precisa de decisão conjunta com `workspace-invitations`; o escopo atual
  importa `memberships` ativos e **nenhum** convite.
