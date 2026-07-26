## Why

Hoje o `in-app-notifications` resolve destinatários por um caminho **fixo** (§2.7 +
a EXTENSÃO do dono): os responsáveis atuais da tarefa (menos o autor), mais o dono
do workspace nos avanços. Não há como uma pessoa **calibrar** o que recebe. O dono
pediu, textualmente: *"que as pessoas trabalhando no robô possam escolher se querem
receber notificações daquele robô, célula, ou projeto como um todo."* — ou seja,
**preferência de notificação por entidade da hierarquia, por pessoa**.

Duas direções, ambas necessárias:

- **Silenciar** um galho que hoje me notificaria (sou responsável, mas aquele robô
  é ruído). Sem isso, quem tem muitas tarefas afoga no sino.
- **Seguir** um galho que hoje **não** me notifica (não sou responsável, mas quero
  acompanhar aquele projeto). Sem isso, um gestor que delegou não enxerga o avanço.

Junto disso, os **dois itens pendentes do dono** — parados no limite de migração na
EXTENSÃO de `in-app-notifications` (`EXECUCAO.md §EXTENSÃO`) — pertencem ao mesmo
subsistema e ao mesmo pipeline de destinatários, então entram na mesma change para o
dono decidir tudo de uma vez:

1. **Notificar ATRIBUIÇÃO a terceiros** (o dono/seguidores querem saber quando alguém
   é atribuído, não só o atribuído). A string atual é 2ª pessoa
   (`%{author} atribuiu **você**…`) e mentiria para quem não é o atribuído.
2. **Notificar EDIÇÕES ESTRUTURAIS** (criar/editar/excluir projeto/célula/robô/
   tarefa) — hoje **não emitem evento algum**; só `task.advanced` e
   `task.assignees_changed` existem.

Cobre a ESPECIFICACAO §2.7 (regras de notificação) e §4.1 (matriz de autorização;
invariante 4). Nenhuma tradução de Firebase nova — o legado **não tinha** preferências
(era não-objetivo explícito de `in-app-notifications`); esta é uma capacidade **além**
do porte, pedida pelo dono.

## What Changes

- **Tabela nova `notification_subscriptions`** (uuid PK, `workspace_id NOT NULL` + RLS
  forçada — D2; FKs compostas por `workspace_id` — padrão de `task_assignees`). Alvo
  por **três colunas FK** (`scope_project_id`/`scope_cell_id`/`scope_robot_id`, exatamente
  uma preenchida por CHECK) — **não** polimórfico textual, pelo mesmo motivo que o `ctx`
  de `notifications` é 4 colunas e não jsonb (integridade referencial de graça, D-N2).
  Estado `follow`/`mute` (enum PG). Índices únicos parciais por alvo (uma preferência por
  pessoa por entidade) + índices de lookup do resolver. **[MIGRAÇÃO — G1]**
- **Semântica de resolução: o mais específico vence.** Para uma notificação num galho
  `projeto → célula → robô`, a linha da pessoa no nível **mais específico** com preferência
  explícita decide (robô > célula > projeto). Sem linha → **DEFAULT**. Permite *seguir um
  robô dentro de um projeto silenciado* e *silenciar um robô dentro de um projeto seguido*.
- **DEFAULT preserva o comportamento atual:** responsável recebe; dono recebe avanços
  (a EXTENSÃO); quem não é nenhum dos dois **não** recebe — salvo se `follow`.
- **`RecipientResolver`/`CreateService` passam a honrar as preferências** sem violar as
  invariantes (dedup, nunca-o-autor, best-effort, RLS). O filtro entra **depois** de montar
  os candidatos e o `ctx` (o ponto `insert_for` já tem project/cell/robot à mão). **[sem migração — G2]**
- **API pessoal de preferência** — `GET` (hidratar os sinos) e `PUT` (upsert; `state:'default'`
  apaga a linha). `NotificationSubscriptionPolicy`: cada pessoa gerencia **só a própria**
  preferência (mesmo idioma do `mark_read?`). **[sem migração — G3]**
- **UX (impeccable):** controle **seguir/silenciar** (sino com estado) no cabeçalho das telas
  de robô, célula e projeto, com o estado **efetivo** e sua **origem** (ex.: "Silenciado pelo
  projeto" quando herdado). **[sem migração — G4]**
- **Item pendente 1 — atribuição a terceiros:** destinatários de `assign` passam a incluir
  dono + seguidores do galho (menos o atribuído e o autor), com uma **chave de locale nova**
  em 3ª pessoa (`assign_observer`). O `type` do enum **continua `assign`** (a `msg` é
  materializada por destinatário) — **não precisa de migração de enum**. **[sem migração — G5]**
- **Item pendente 2 — eventos estruturais:** criar/editar/excluir projeto/célula/robô/tarefa
  passam a instrumentar evento pós-commit; novo valor de enum `notification_type` +
  strings de locale; destinatários = dono + seguidores do galho (menos o autor), honrando
  `mute`. **[MIGRAÇÃO de enum — G6; reversão NÃO-trivial]**

### Não-objetivos

- **Preferência por TIPO** ("não me avise de `progress`, só `done`"). O eixo desta change
  é **entidade** (galho da hierarquia), não tipo. Fica para depois.
- **E-mail / Web Push / SMS / digest.** Seguem não-objetivos de `in-app-notifications`.
- **Preferência de OUTRA pessoa.** Cada um só edita a própria (política, não UI).
- **Transporte em tempo real** do sino (a lista já invalida por `realtime-collaboration`).
- **Migrar `notification_type` de enum PG para texto+CHECK.** Fora de escopo; conviver com
  `ALTER TYPE ADD VALUE` e registrar o custo de reversão (G6).

## Capabilities

### New Capabilities

- `notification-preferences`: o modelo `notification_subscriptions`, a semântica de
  resolução (mais-específico-vence + default), a API pessoal, e o controle seguir/silenciar
  na UI das três telas de hierarquia.

### Modified Capabilities

- `in-app-notifications`: o `RecipientResolver`/`CreateService` passam a filtrar candidatos
  pelas preferências; `assign` ganha destinatários observadores (dono/seguidores) com chave
  de locale em 3ª pessoa; novos eventos estruturais com novo valor de enum.

### Impact

- **Depende de** `in-app-notifications` (COMPLETO): pipeline, `notifications`, invariantes
  4/8, `NotificationPolicy`, `NotifyTaskEventJob`, locale versionado.
- **Depende de** `commissioning-hierarchy` (COMPLETO): `projects`/`cells`/`robots` com
  `UNIQUE (id, workspace_id)` — alvo das FKs compostas.
- **Depende de** `workspace-tenancy` (COMPLETO): `Person`, `workspace_id`, RLS (D2),
  `WorkspaceScoped`.
- **Depende de** `authorization-policies` (COMPLETO): nova action na `PermissionMatrix` +
  `NotificationSubscriptionPolicy` no route-sweep.
- **Toca** `hierarchy-screens` e `robot-task-table`: o controle mora no cabeçalho das telas.
- **Reversão:** G1 (tabela nova) reverte por `DROP TABLE` — barato. **G6 (novo valor de
  enum) NÃO reverte trivialmente** — remover valor de enum PG exige recriar o tipo. É o
  único ponto onde a reversão deixa de ser um `down` simples; marcado como tal em `tasks.md`.
