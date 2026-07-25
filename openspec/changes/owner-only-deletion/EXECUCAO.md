# EXECUÇÃO — `owner-only-deletion`

Reconciliação **design × realidade** antes de qualquer código, conforme o método da casa
(`CLAUDE.md`: "Antes de qualquer código, `EXECUCAO.md` reconciliando design × realidade,
commit `G0`"). Tudo abaixo foi **lido no repositório**, não suposto; onde há suposição, ela
está marcada como tal e virou tarefa de verificação.

## 1. O pedido, em uma linha

O dono pediu: **só o dono apaga; o editor edita mas não apaga.** Duas decisões de escopo
foram tomadas por ele nesta rodada, antes do desenho:

| Pergunta | Resposta do dono |
|---|---|
| Abrangência | **Só a hierarquia** (projeto/célula/robô/tarefa). Catálogo — pessoas e modelos de tarefa — fica como está |
| Onde travar | **Policy + banco** (gatilho), não só a policy |

## 2. Realidade encontrada (o ponto de partida verdadeiro)

### 2.1 O editor HOJE pode apagar — e isso não é bug

`app/policies/permission_matrix.rb` codifica 8 actions. As quatro policies de hierarquia
mapeiam `destroy?` para `manage_commissioning`, que é `%i[owner edit]`:

```
project_policy.rb:10   destroy?: :manage_commissioning
cell_policy.rb:9       destroy?: :manage_commissioning
robot_policy.rb:9      destroy?: :manage_commissioning
task_policy.rb:10      destroy?: :manage_commissioning
```

Isso implementa **corretamente** a §4.1 L2 da ESPECIFICACAO.md ("criar/editar/excluir
projeto, célula, robô, tarefa — `owner`, `edit`"). Portanto esta change é **divergência
deliberada da spec legada**, não correção. A distinção importa para o tom de tudo que for
escrito: não há nada a consertar, há uma regra a endurecer.

### 2.2 Apagar já é arquivar

`Hierarchy::CrudService#destroy` (linhas 66-82) **não** chama `destroy!`: audita, captura a
referência do pai, chama `Hierarchy::SoftDeleteService` e recomputa o progresso, tudo numa
transação, devolvendo 204. O `SoftDeleteService` arquiva a subárvore de baixo para cima com
um `UPDATE` por nível (`deleted_at`, `position = NULL`, sem bump de `lock_version`).

**Consequência de desenho, e é a mais importante desta change:** o gatilho de banco NÃO
pode ser `BEFORE DELETE` — não há `DELETE`. Tem de ser `BEFORE UPDATE` observando a
**transição** `deleted_at: NULL → NOT NULL`. Um desenho feito "de cabeça", assumindo hard
delete, teria produzido um gatilho que nunca dispara — e uma suíte verde provando nada.

### 2.3 O banco já sabe quem é o usuário

`app/lib/tenant.rb` emite `SET LOCAL` de **duas** variáveis dentro da transação do request:
`app.current_workspace_id` e `app.current_user_id`. A segunda já é usada em produção nas
políticas de RLS de `memberships` e `membership_revocations`. É ela que torna o gatilho
possível sem inventar canal novo.

### 2.4 Existem dois precedentes exatos para a forma do gatilho

- `memberships_owner_is_not_member()` — faz `SELECT owner_user_id FROM workspaces WHERE
  id = NEW.workspace_id` e levanta com mensagem citando a spec. **Mesma consulta** que o
  gatilho novo precisa.
- `workspaces_owner_immutable()` — regra de **transição** (`NEW.x IS DISTINCT FROM OLD.x`),
  implementada como gatilho e não como RLS. **Mesma natureza** da regra nova.

E um precedente para a válvula: a política `purge_expired ON invitations` usa
`current_setting('app.invitation_purge', true) = 'on'`. O nome
`app.hierarchy_archive_bypass` é o irmão direto dele.

### 2.5 Um `if` na policy seria reprovado mecanicamente

`spec/authorization/role_comparison_guard_spec.rb` falha o CI diante de qualquer
`role ==` em `app/` fora de `permission_matrix.rb`. A solução por matriz não é preferência
estética: é a única que passa no CI existente.

### 2.6 A UI expõe menos exclusão do que parece

Varredura de `Excluir` no frontend (fora de testes) encontrou **dois** pontos de exclusão
de hierarquia:

- `app/pages/ProjectPage.tsx:89` — `IconButton icon="trash" label={`Excluir ${cell.name}`}`
- `features/robot-tasks/AcoesCell.tsx` — ação "Excluir" da tabela de tarefas do robô

Não há botão de excluir **projeto** nem de excluir **robô** na interface atual (o hook
`useDeleteProject` existe em `features/hierarchy/useHierarchy.ts:125`; não há
`useDeleteRobot`). O backend, porém, expõe os quatro endpoints — daí o G1 cobrir os quatro
e o G3 cobrir só os dois que existem na tela. **Escopo de UI menor que o de servidor é
intencional, não omissão.**

### 2.7 Papel no cliente é rótulo

`store/workspaceStore.ts:14` traz o comentário `role: string // rótulo, não autoridade`, e
`AppShell.tsx:249` já deriva `canManage` dele. O G3 acrescenta um irmão, mantendo a mesma
ressalva — coerente com a invariante 1 da §4.1.

## 3. Afirmações que deixam de ser verdadeiras (reconciliadas, não escondidas)

### DE-G0.1 — "A matriz §4.1 tem 8 linhas"

Afirmado em `proposal.md` de `authorization-policies` ("as 8 linhas da tabela viram 8
actions"), no comentário de cabeçalho de `permission_matrix.rb` ("Oito chaves, uma por
linha da tabela"), em `permission_matrix_spec.rb` ("codifica as 8 linhas da §4.1") e na
grade de 24 células de `matrix_conformance_spec.rb`.

**Decisão:** a matriz passa a ter **9** actions. A §4.1 L2 fica representada por duas
(`manage_commissioning` para criar/editar; `destroy_commissioning` para excluir), e o
comentário da linha nova nomeia a divergência e a change que a introduziu. O comentário de
cabeçalho e os dois specs são atualizados no MESMO commit (G1.1, G1.3, G1.4). O
`proposal.md` de `authorization-policies` **não** é reescrito — é registro histórico do que
aquela change entregou; a reconciliação vive aqui e no comentário do código.

### DE-G0.2 — `legacy_parity.yml`, entrada `L42 — projects allow write`

Hoje: `covered_by: "matrix_conformance_spec — manage_commissioning (célula: view false,
edit true); HTTP pending por commissioning-hierarchy"`.

**Decisão:** migra para `divergence`, explicando que o verbo único `write` do Firestore foi
dividido pelo porte e que a exclusão foi endurecida para o dono. As 22 entradas são
mantidas — `legacy_parity_spec.rb` exige a contagem exata, e a regra legada continua sendo
uma só; o que muda é como o porte a honra (G1.5).

### DE-G0.3 — Nenhuma spec de UI afirma que o editor apaga

Verificado: nenhum requisito publicado promete o controle de exclusão ao papel `edit`. O
G3 não contradiz spec existente. A varredura de `.md` atrás de runbook que mande um editor
apagar algo continua obrigatória no fechamento (G4.2) — a ausência aqui foi conferida no
`openspec/`, não no corpo inteiro da documentação.

## 4. Decisões de execução tomadas antes do código

- **DE-1 — Gatilho em `BEFORE UPDATE`, não `BEFORE DELETE`** (consequência de §2.2). É a
  decisão que separa um gatilho que funciona de um que nunca dispara.
- **DE-2 — Contexto vazio nega.** Sessão sem `app.current_user_id` e sem a válvula levanta.
  Fail-closed é a postura de toda esta base (`BasePolicy` sem predicado default, `allows?`
  com `KeyError`, rota sem `route_setting` que levanta). A alternativa — "sem contexto,
  deixa passar" — anularia o gatilho para todo script, job e console, que é exatamente o
  conjunto de chamadores que ele existe para pegar.
- **DE-3 — Válvula nomeada, não implícita.** `app.hierarchy_archive_bypass = 'on'`, ligada
  explicitamente em seed, restauração de backup e `Legacy::*`. Quem a usa escreveu que a
  estava usando, e um `grep` acha todos os pontos.
- **DE-4 — 403 para o editor, 404 só para cross-tenant.** `BasePolicy#authorize!` já faz a
  distinção; a change a exercita num caso novo e a prende com cenário. Não inverter: a
  regra da casa sobre 404 vale para **vazamento entre tenants**, e o valor dela depende de
  o 403 continuar significando "existe, você é membro, seu papel não alcança".
- **DE-5 — Ocultar o controle, não desabilitá-lo.** Botão desabilitado não recebe foco nem
  é anunciado, então o "porquê" não chega a quem usa teclado ou leitor de tela; e num alvo
  de 32px usado de luva, um controle que não executa é ruído.
- **DE-6 — Migration não é destrutiva.** `CREATE FUNCTION` + quatro `CREATE TRIGGER`, com
  `down` que derruba os dois. Não apaga dado, não altera coluna, não reescreve tabela —
  logo **não exige tarefa de backup antes** (a regra da casa é explícita sobre tarefa
  destrutiva; esta não é uma).
- **DE-7 — Escopo de UI menor que o de servidor.** As quatro policies mudam; só dois
  controles existem para esconder (§2.6). Deliberado.

## 5. Suposição única, e como ela vira prova

**Suposição:** o reset de fábrica (`workspace-settings`) passa pelo gatilho sem precisar da
válvula, porque é endpoint HTTP autorizado por `destroy_workspace` (dono) rodando dentro da
transação de tenant que já emitiu `SET LOCAL app.current_user_id` do dono.

É a única afirmação do design que ainda não foi verificada executando. Virou a tarefa
**G2.4**, com o desfecho já decidido nos dois sentidos: se a prova falhar, a decisão passa a
ser "o reset também liga a válvula" e é registrada aqui — **nunca corrigida em silêncio**
(regra 4 do método).

## 6. Mapa de grupos

| Grupo | Entrega | Prova que fecha o grupo |
|---|---|---|
| **G0** | Planejamento OpenSpec + esta reconciliação | `validate --strict` verde |
| **G1** | 9ª action, quatro policies remapeadas, conformidade e paridade atualizadas | Specs de request (403/404/204) + guard/sweep/cross-tenant/parity/invariantes verdes |
| **G2** | Gatilho nas quatro tabelas + válvula nos caminhos de manutenção | Specs de banco + `migrate`/`rollback`/`migrate` limpos + prova do reset (G2.4) |
| **G3** | Controles de exclusão ocultos para não-dono | vitest dirigido + sweeps + `tsc`/`lint` |
| **G4** | E2E, documentação, fechamento | `e2e:lint`, docs sem afirmação falsa, `validate --strict`, resumo pt-BR |

## 7. Registro de execução

- **G0 — feito.** Change materializada (`README.md`, `proposal.md`, `design.md`,
  `specs/owner-only-deletion/spec.md`, `tasks.md`, este arquivo). Nenhum código de aplicação
  tocado: G0 é planejamento, por método. As decisões de escopo do dono (§1) e as duas
  divergências (DE-G0.1, DE-G0.2) ficam registradas antes da primeira linha de Ruby.
