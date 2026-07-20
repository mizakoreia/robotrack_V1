## Context

Esta capacidade é o coração da regra de negócio e está no caminho crítico
(`robot-tasks → progress-advances → progress-rollup → robot-task-table → offline-pwa`).
Três capacidades da Onda 6 consomem o evento que produzimos; duas da Onda 7 renderizam a
trilha que gravamos; `offline-pwa` depende das nossas escolhas de identificador e de
timestamp para poder existir.

O legado (PWA vanilla + Firestore) expressava tudo isto no cliente: o array `history`
vivia dentro do documento da tarefa, a obrigatoriedade do comentário era um `if` no
handler do botão do modal, a imutabilidade da trilha era um costume, e o timestamp era
`serverTimestamp()`. Nenhuma dessas quatro coisas sobrevive ao porte como estava. O
trabalho aqui é decidir, para cada uma, **onde a invariante passa a morar**.

Restrições herdadas e não renegociáveis: D1 (uuid gerável no cliente), D2 (`workspace_id`
NOT NULL + RLS), D3 (policy objects singleton, sem Pundit), D6 (evento no
`WorkspaceChannel`), D8 (dois timestamps — somos os donos), D10 (`Person` é a identidade),
D11 (sem sentinela `"Não Atribuído"`), D14 (strings pt-BR centralizadas).

## Goals / Non-Goals

**Goals**

- Tornar `task_advances` a **única** origem possível de uma mudança de `tasks.progress`.
- Fazer com que a trilha seja verdadeiramente inalterável, inclusive para o dono do
  workspace e para quem tem acesso ao console da aplicação.
- Dar ao par status↔progresso um comportamento único, testável e sem caminho paralelo,
  incluindo a exceção `N/A`.
- Deixar o registro de avanço seguro para retentativa (offline, rede instável, duplo
  clique) sem produzir entrada dupla na trilha.
- Entregar a `robot-task-table` e ao relatório um contrato de leitura estável e ordenado.

**Non-Goals**

- Agregação de progresso (é `progress-rollup`, D5), redação de notificação
  (`in-app-notifications`), formato da mensagem de auditoria (`audit-log`), renderização
  do modal de histórico e dos avisos (`robot-task-table`), importador
  (`legacy-data-migration`), fila offline (`offline-pwa`).
- Edição de avanço. Não existe e não vai existir; ver D-IMUT.

## Decisions

### D-TS — Dois timestamps, e `recorded_at` é a verdade exibida (dono de D8)

`task_advances` tem `recorded_at timestamptz NOT NULL` e `created_at timestamptz NOT NULL
DEFAULT now()`. O cliente envia `recorded_at` no momento em que a pessoa confirma o modal;
o servidor nunca o sobrescreve. Toda leitura de trilha e o relatório de comissionamento
(§3.8) exibem `recorded_at`. `created_at` só aparece em auditoria e depuração.

Resposta explícita ao caso que o `serverTimestamp()` do Firestore respondia e o porte
precisaria responder: **avanço registrado offline às 14h e sincronizado às 17h é exibido
como 14h**, e `created_at` guarda 17h. A diferença fica auditável, e um item da trilha
sincronizado com atraso > 1h ganha, no contrato de leitura, o campo derivado
`synced_late: true` para que `robot-task-table` possa marcá-lo.

Guardas — porque um timestamp de cliente é entrada não confiável:
- `recorded_at` ausente ⇒ servidor usa `now()` (não é erro; é o caminho online normal
  quando o cliente não tem relógio confiável).
- `recorded_at > now() + ADVANCE_RECORDED_AT_SKEW_MINUTES` (padrão 10 min) ⇒ **clamp**
  para `created_at`, e grava `recorded_at_adjusted = true`. Rejeitar seria pior: perderia
  o avanço de um celular com relógio errado.
- `recorded_at < now() - 90 dias` ⇒ mesmo clamp. Uma fila offline com 90 dias já é
  poison message e é problema de `offline-pwa`.
- `recorded_at` nunca é menor que `recorded_at` da entrada anterior da mesma tarefa? **Não
  impomos.** Duas pessoas offline podem registrar fora de ordem, e reescrever a hora de
  alguém para forçar monotonicidade é falsificar o registro. A ordenação de leitura
  resolve empates de forma determinística (ver D-ORD).

**Alternativa descartada:** um único `created_at` de servidor, como o legado. Descartada
porque destrói a proposta de valor do modo offline — o engenheiro que registra no chão de
fábrica veria, no relatório assinado, o horário em que voltou o sinal do Wi-Fi.

**Alternativa descartada:** confiar cegamente no `recorded_at` do cliente sem clamp.
Descartada porque um relógio errado (comum em tablet de galpão) colocaria entradas em
2038 no topo permanente da timeline.

**Onde mora:** colunas `NOT NULL`; clamp no `TaskAdvances::CreateService`; `NOT NULL` +
`CHECK (recorded_at <= created_at + interval '10 minutes')` no banco como rede de
segurança contra qualquer outra porta de escrita.

### D-ORD — Ordenação determinística da trilha

Leitura ordena por `recorded_at DESC, created_at DESC, id DESC`. O terceiro critério
existe porque dois avanços da mesma tarefa podem colidir em ambos os timestamps quando
sincronizados em lote. Índice: `(task_id, recorded_at DESC, created_at DESC, id DESC)`.

**Alternativa descartada:** ordenar por `created_at` (ordem de chegada). Descartada porque
contradiz D-TS: a timeline mostraria uma ordem diferente das horas que ela própria exibe.

### D-SM — A máquina de estados é um serviço transacional, **não** `aasm`

A gem `aasm` está no Gemfile e **não é usada aqui**. Motivo: `aasm` modela transições
disparadas por *eventos* sobre uma única coluna de estado, com guards e callbacks. O que
§2.2 descreve é um **acoplamento bidirecional entre duas colunas** — `status` deriva de
`progress` e `progress` deriva de `status`, e qual das duas é a entrada depende de qual o
usuário mexeu. Modelar isso em `aasm` exigiria eventos sintéticos por faixa de progresso
(`to_zero`, `to_partial`, `to_hundred`), um callback que escreve `progress` dentro da
transição de `status`, e um segundo callback que dispara a transição de `status` a partir
de uma escrita em `progress` — com risco real de recursão e com a exceção do `N/A`
(progresso 0 preservando `N/A`) virando um guard que depende do estado de origem *e* do
valor numérico. O ganho de `aasm` (declaratividade, `may_x?`, log de transição) não paga
esse contorcionismo.

Fica então: `Tasks::ApplyTransitionService.call(task:, actor:, progress: nil, status: nil)`
— singleton no idioma dos services do template (`ApiResponseHandler`), recebe **exatamente
um** dos dois (`progress` XOR `status`), retorna o par `(status, progress)` resolvido.
Tabela-verdade, direta e testável linha a linha:

| entrada | resultado |
|---|---|
| `status = Concluído` | `progress = 100` |
| `status = N/A` | `progress = 0` |
| `status = Pendente` | `progress = 0` |
| `status = Em Andamento` | `progress` inalterado |
| `progress = 100` | `status = Concluído` + evento de auditoria |
| `0 < progress < 100` | `status = Em Andamento` |
| `progress = 0` **e** status atual `≠ N/A` | `status = Pendente` |
| `progress = 0` **e** status atual `= N/A` | `status = N/A` (preservado) |

**Alternativa descartada:** `aasm` (justificativa acima). **Alternativa descartada:**
trigger de banco calculando o par. Descartada porque a transição para 100 precisa gravar
auditoria com o nome do ator e a descrição da tarefa — lógica de aplicação e i18n dentro
de PL/pgSQL é dívida pior que a que resolve.

**Onde mora:** serviço (cálculo) + CHECK constraint em `tasks` (ver D-CHK) como rede
contra qualquer outra porta de escrita.

### D-CHK — Qual coerência status↔progresso vira CHECK, e qual não vira

Vira constraint apenas o lado **incondicionalmente verdadeiro**:

```sql
ALTER TABLE tasks ADD CONSTRAINT tasks_done_implies_full
  CHECK (status <> 'Concluído' OR progress = 100);
```

O lado inverso (`progress = 100 ⇒ status = 'Concluído'`) **não** vira constraint, e isso é
deliberado: reabrir uma tarefa concluída é ação legítima (`status = Em Andamento`, e por
§2.2 o progresso fica *inalterado*, portanto 100). Uma bi-implicação tornaria a reabertura
impossível sem inventar um valor de progresso que a spec não autoriza. Idem para
`Em Andamento ⇒ 0 < progress < 100`: setar `Em Andamento` numa tarefa em 0% é alcançável e
válido pela própria tabela de §2.2. Portanto: o par `(Em Andamento, 0)` e o par
`(Em Andamento, 100)` são estados **legítimos** do sistema e nenhum teste pode tratá-los
como corrupção.

**Alternativa descartada:** CHECK de bi-implicação total. Descartada por tornar a
reabertura de tarefa impossível — o modo de falha seria um `PG::CheckViolation` na cara do
engenheiro que percebeu que a solda precisava de retrabalho.

### D-CMT — Comentário obrigatório abaixo de 100 é CHECK constraint

```sql
CHECK (to_progress = 100 OR legacy OR (comment IS NOT NULL AND btrim(comment) <> ''))
CHECK (char_length(comment) <= 1000)
```

Espaço em branco não satisfaz a regra (`btrim`). O model tem a validação equivalente só
para produzir mensagem pt-BR de 422 antes de o banco reclamar — a **garantia** é a
constraint. A isenção de `legacy` é o contrato com `legacy-data-migration` (D-LEG): a nota
importada tem `to_progress = 0` e o texto da nota como `comment`, então na prática ela
satisfaria a regra de qualquer forma; a isenção existe para o caso de `obs` vazio-mas-
presente no export.

Limite de 1000 chars: o comentário entra na mensagem de notificação, que é limitada a 500
por §4.1 inv. 8. **Truncar é responsabilidade de `in-app-notifications`**, não nossa —
mutilar o registro de comissionamento para caber num toast seria inverter a prioridade.

**Alternativa descartada:** só `validates :comment, presence: true, if: -> { to < 100 }`.
Descartada por §5 da barra: um `TaskAdvance.new(...).save(validate: false)` no console
fura, e a auditoria de comissionamento perde a razão de existir.

### D-IMUT — Imutabilidade em três camadas, nenhuma delas convenção

1. **RLS (D2):** as policies de `task_advances` cobrem `SELECT` e `INSERT` e mais nada.
   Sem policy de `UPDATE`/`DELETE`, o Postgres nega por omissão para o role da aplicação.
2. **`REVOKE UPDATE, DELETE ON task_advances FROM <app_role>`** — explícito, para que a
   negação não dependa de alguém não desligar RLS numa migration futura.
3. **Trigger `BEFORE UPDATE OR DELETE ... FOR EACH ROW EXECUTE` que faz `RAISE EXCEPTION`**
   — pega o caminho que as duas anteriores não pegam: migration rodando como owner da
   tabela, `psql` administrativo, `rails db:seed` em produção.

Consequência assumida: **não existe `DELETE` de avanço nem em cascata**. Excluir uma
tarefa (`robot-tasks`) não pode ser `ON DELETE CASCADE` sobre `task_advances`, porque o
trigger recusaria e a exclusão da tarefa falharia. Contrato acordado: `tasks` usa
**soft-delete** (`deleted_at`) e a FK é `ON DELETE RESTRICT`. Isto é um **requisito que
devolvemos a `robot-tasks`** e está listado como pergunta em aberto Q1 caso lá se tenha
optado por hard delete.

**Alternativa descartada:** `paper_trail` (já instalado no template) para versionar
avanços. Descartada porque versionar pressupõe que editar é permitido; aqui editar é o
que estamos proibindo. `paper_trail` continua irrelevante para esta capacidade.

### D-ID — Idempotência por uuid do cliente, antes do controle de concorrência

O `id` do avanço é uuid gerado no cliente (D1). O endpoint resolve nesta ordem:

1. Se já existe `task_advances.id = <uuid>` no workspace corrente → responde `200` com o
   avanço existente e o estado atual da tarefa. **Não** cria segunda entrada, **não**
   reaplica a transição, **não** re-notifica.
2. Senão, compara `lock_version` recebido com o da tarefa. Divergente → `409` (D-409).
3. Senão, cria, aplica transição, auto-atribui, incrementa `lock_version`, commita.

A ordem importa: se a checagem de `lock_version` viesse primeiro, uma retentativa de um
POST que **já teve sucesso** (resposta perdida na rede do galpão) veria `lock_version`
desatualizado e responderia 409, e a UI mandaria o engenheiro resolver um conflito
inexistente consigo mesmo. Esse é o modo de falha concreto que a ordem inverte.

**Alternativa descartada:** header `Idempotency-Key` separado do id do recurso.
Descartada por redundância — D1 já obriga o cliente a saber gerar o uuid, e um segundo
identificador só criaria a possibilidade de eles discordarem.

### D-409 — Semântica de conflito e o que a UI faz com ela

O cliente envia `lock_version` da tarefa como ela estava quando o modal abriu. Divergência
→ `409 Conflict`, corpo:

```json
{ "error": "conflito_de_versao",
  "task": { "id": "...", "progress": 70, "status": "Em Andamento", "lock_version": 8 },
  "latest_advance": { "author_name_snapshot": "Ana", "to_progress": 70,
                      "recorded_at": "...", "comment": "..." } }
```

409 **não é erro de rede e não descarta o que a pessoa escreveu.** A UI mantém o
comentário digitado, substitui o corpo do modal por: "Ana registrou 70% enquanto você
escrevia", e oferece duas ações — *Recalcular a partir de 70%* (reaplica o mesmo delta
sobre o novo valor e **gera um novo uuid de avanço**, porque é outro fato) ou *Descartar*.
Nunca reenvia automaticamente: reaplicar +10 sobre um valor que outra pessoa acabou de
mudar sem o operador ver é exatamente como se perde um registro de comissionamento.

**Alternativa descartada:** last-write-wins (comportamento efetivo do Firestore no legado).
Descartada porque com dois engenheiros no mesmo robô — o caso normal, não o excepcional —
o progresso vira sorteio.

**Onde mora:** `lock_version` é coluna criada por `robot-tasks`; o `ActiveRecord::StaleObjectError`
é capturado no serviço e traduzido a 409 no `rescue_from` do Grape; o teste que prova é um
spec de request com duas sessões.

### D-AUTO — Auto-atribuição na mesma transação, e o que sobra da "lista do workspace"

§2.3: alterar progresso ou status de tarefa **sem nenhum responsável** atribui o autor. No
porte: se `task_assignees` da tarefa está vazio, insere `(task_id, person_id = actor.person_id)`
dentro da mesma transação do avanço. Se já há **qualquer** responsável — mesmo que não seja
o autor — não mexe.

A segunda metade de §2.3 ("adiciona seu nome à lista de responsáveis do workspace") é um
artefato do modelo legado, onde responsável era string e o workspace mantinha um array de
nomes. Com D10/D11 essa lista é `people` do workspace, e o autor **já é** uma `Person` (foi
criada no bootstrap ou no aceite do convite). A operação portanto **colapsa em no-op** — e
isso é uma decisão declarada, não um esquecimento: o serviço faz um `find_or_create`
idempotente da `Person` do ator no roster e há um teste que prova que o roster não ganha
duplicata nem entrada de nome solto.

**Alternativa descartada:** atribuir o autor em *toda* mudança, mesmo com responsável já
presente. Descartada por contrariar §2.3 literalmente e por inflar a lista de destinatários
de notificação a cada avanço.

**Onde mora:** serviço + índice único `(task_id, person_id)` em `task_assignees` (de
`robot-tasks`) garantindo que a corrida de dois avanços simultâneos não duplique.

### D-LEG — §1.4 item 2 vai para o importador, e isto é uma mudança de requisito consciente

**O que o legado fazia:** em runtime e preguiçosamente — no *primeiro* registro de avanço
de uma tarefa que tivesse `obs` preenchido e `history` vazio, convertia `obs` na primeira
entrada com `byName: "(nota anterior)"` e `legacy: true`, e removia `obs`.

**O que decidimos:** a conversão acontece **no importador em lote**
(`legacy-data-migration`), de uma vez, no momento do import. **`tasks` não tem coluna
`obs`.**

Isto **muda o requisito** e não vale fingir que não. Diferenças observáveis:

| | legado (lazy) | porte (import) |
|---|---|---|
| Tarefa com `obs` que nunca recebe avanço | nota fica invisível na trilha para sempre | nota aparece na trilha desde o dia 1 |
| Ordem da entrada legada | sempre a primeira | sempre a primeira (`recorded_at` = timestamp legado da tarefa, ou o do import) |
| Estado do esquema | `obs` existe e some com o tempo | `obs` nunca existe |

Justificativa: manter o comportamento lazy exigiria uma coluna `obs` viva em `tasks`, uma
condição especial no caminho mais quente do sistema (todo registro de avanço checaria
`obs.present? && advances.empty?`), e um esquema que só termina de migrar quando o último
usuário mexer na última tarefa — ou seja, nunca. A diferença observável é estritamente
favorável ao usuário. O que **não** é aceitável é o que o plano anterior fez: mover isso
para o importador **em silêncio**, sem registrar que o requisito mudou.

Contrato da entrada legada (é isto que `legacy-data-migration` implementa):
`by = NULL`, `author_name_snapshot = '(nota anterior)'`, `legacy = true`,
`from_progress = 0`, `to_progress = 0`, `comment = <conteúdo de obs>`,
`recorded_at = <timestamp legado ou do import>`. A CHECK
`by IS NOT NULL OR legacy` garante que **só** entradas legadas podem ter autor nulo.

**Aviso formal a `robot-task-table`:** §3.5 descreve o aviso "trilha faltando" como
`0 < progresso < 100 e nenhum histórico **nem nota**`. A cláusula "nem nota" **deixa de
existir** — não há nota fora da trilha. A condição do aviso passa a ser
`0 < progress < 100 AND advances_count = 0`, e `advances_count` conta inclusive entradas
`legacy`. `robot-task-table` deve refletir isso na sua spec.

**Alternativa descartada:** manter a conversão lazy em runtime, fiel ao legado.
Descartada pelos três custos acima. **Alternativa descartada:** importar `obs` como campo
livre e nunca converter. Descartada porque perde a nota do relatório de comissionamento,
que é onde ela tem valor.

### D-UI — Por que o valor do modal é lido do estado atual e não de um cache de render

§2.4 item 1 insiste que o valor dos botões `−10`/`+10` é "lido do estado atual, não de um
valor em cache". O modo de falha concreto: capturar `task.progress` numa closure no mount
da linha, e então dois `+10` seguidos sem recarregar produzirem `45→55` e `45→55` de novo,
em vez de `45→55→65`.

Implementação: o handler do botão não fecha sobre nenhum valor. Ele lê
`queryClient.getQueryData(['ws', wsId, 'robot', robotId, 'tasks'])`, localiza a tarefa por
id e calcula `clamp(0, 100, task.progress ± 10)`. Após o sucesso da mutation, a query key é
invalidada (e o evento do `WorkspaceChannel`, por D6, invalida também para os outros
clientes) — de modo que a segunda leitura já vê 55.

O slider é controlado por `value = draft ?? serverProgress`. Confirmar limpa `draft` e
deixa o valor do servidor assumir; **cancelar limpa `draft`**, o que por construção reverte
o slider ao valor persistido (§2.4 item 5) sem nenhum código de "desfazer".

**Alternativa descartada:** `useState` local espelhando o progresso com `useEffect` de
sincronização. Descartada porque é exatamente a fonte do bug do `+20` e porque duplica
estado de servidor, contra D9.

### D-AUTHZ — Autorização e isolamento

`TaskAdvancePolicy.create?` exige membership no workspace da tarefa com papel `owner` ou
`edit` (§4.1). `view` → `403`, e por §4.1 inv. 4 isso é absoluto: a única mutação de um
`view` é marcar a própria notificação como lida. Tarefa de outro tenant → **`404`**, não
403: a RLS (D2) faz a linha não existir para a sessão, e responder 403 vazaria a existência
do id. Endpoint declara a policy explicitamente para passar no route-sweep de D3.

## Risks / Trade-offs

- **Escrita amplificada.** Todo avanço escreve `task_advances` + `tasks` + possivelmente
  `task_assignees` + `audit_logs`, e enfileira notificação e evento de Cable. Numa
  sincronização offline de 200 itens isso é 200 transações. Mitigação: endpoint de lote
  fica de fora desta entrega (dito aqui explicitamente); `offline-pwa` drena a fila com
  concorrência 1 e backoff. Se virar gargalo, a solução é lote — não é relaxar invariante.
- **Timestamp de cliente é dado não confiável.** Mitigado por clamp (D-TS), mas alguém vai
  perguntar por que a trilha mostra 14h e o log do servidor 17h. Mitigação: contrato de
  leitura expõe `synced_late` e a UI marca a entrada.
- **Trilha nunca encolhe.** Sem `DELETE`, uma tarefa muito movimentada acumula entradas
  indefinidamente. Aceito: a trilha é o produto. Leitura é paginada (50 por página, mais
  recentes primeiro) e o relatório limita por escopo. Retenção é problema de `audit-log`,
  não nosso.
- **Soft-delete obrigatório em `tasks`.** D-IMUT impõe uma restrição a `robot-tasks` que
  ela pode não ter previsto. Ver Q1.
- **409 é uma tela nova que ninguém pediu.** Custo de UI real, e o legado não tinha nada
  disso. Aceito porque a alternativa (last-write-wins) perde registro em silêncio, que é a
  única falha que este produto não pode ter.
- **Ficou de fora conscientemente:** endpoint de avanço em lote; desfazer/reverter avanço
  (a forma de corrigir um erro é registrar outro avanço com comentário); anexo de foto no
  comentário; e `recorded_at` editável pelo usuário.

## Plano de migração

Não há dado em produção — o repositório está em greenfield e o import legado é da Onda 9.
Mesmo assim, a ordem importa e cada passo é reversível:

1. Migration A: cria `task_advances` com colunas, FKs, CHECKs e índices. Reversível
   (`drop_table`).
2. Migration B: habilita RLS e cria policies de `SELECT`/`INSERT` (nenhuma de
   `UPDATE`/`DELETE`), conforme D2.
3. Migration C: `REVOKE UPDATE, DELETE` + trigger de imutabilidade. **Depois** de A e B,
   nunca antes — senão as próprias migrations seguintes esbarram no trigger.
4. Migration D: `CHECK tasks_done_implies_full` em `tasks`. Precede-a uma tarefa de
   verificação que roda `SELECT count(*) FROM tasks WHERE status = 'Concluído' AND
   progress <> 100` e exige `0`; se houver linhas (import já rodado), a migration é
   abortada e o dado é corrigido antes — nunca com `NOT VALID` silencioso.
5. Rollback: C → B → A, nessa ordem. Derrubar o trigger antes de qualquer coisa é
   pré-condição de qualquer rollback, e isso está escrito na `down` de C.

## Perguntas em aberto

- **Q1 (para `robot-tasks`):** `tasks` usa soft-delete? D-IMUT exige que sim (FK
  `ON DELETE RESTRICT`). Se lá se optou por hard delete, uma das duas specs precisa mudar,
  e a nossa não pode.
- **Q2 (para `progress-rollup`):** o recálculo de `progress_cache` do robô ocorre dentro
  da nossa transação (consistente, mais lento) ou em job pós-commit (rápido, janela de
  inconsistência)? Publicamos o evento das duas formas; a escolha é de D5.
- **Q3 (para `commissioning-report`):** o relatório exibe entradas `legacy` com o rótulo
  "(nota anterior)" literal, ou com marcação visual própria? O dado está lá dos dois jeitos.
- **Q4 (para `in-app-notifications`):** truncamento de comentário > 500 chars na mensagem
  — elipse no fim ou omissão do comentário? Não truncamos na origem (D-CMT).
