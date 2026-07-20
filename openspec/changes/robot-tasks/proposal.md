## Why

A tarefa é a unidade atômica do RoboTrack: tudo que o produto mede (§2.1), exibe
(§3.5) e relata (§3.8) sobe a partir dela. Esta capacidade cobre §1.1 (entidade
Tarefa), §2.5 (criação de robôs em lote com cópia das tarefas-base filtradas pela
Aplicação), §3.5 (as colunas de dado da tabela do robô — não o visual) e §1.4
item 1 (compatibilidade de leitura de responsáveis legados).

Ela também corrige o **defeito estrutural central do legado**: responsáveis eram
endereçados **por texto**. O Firestore guardava `assignees` como lista de *nomes*,
mais um campo legado `resp` de responsável único, mais o sentinela
`"Não Atribuído"` como valor válido. Renomear uma pessoa órfãnava suas
atribuições; duas pessoas homônimas eram a mesma pessoa; e o sentinela poluía
consultas de "Minhas Tarefas" e notificações. Por **D10** e **D11**, o alvo
endereça responsáveis por `people.id` e representa ausência de responsável como
**conjunto vazio** — não como um nome mágico.

O que este porte traduz de Firebase: o array `tasks` aninhado no documento do
robô vira tabela relacional `tasks` com `position`; o array de nomes `assignees`
vira a tabela de junção `task_assignees (task_id, person_id)`; e as
security rules que só protegiam a raiz do documento do workspace viram RLS por
`workspace_id` (**D2**) mais policies server-side (**D3**).

## What Changes

- **Tabela `tasks`** (uuid PK gerável no cliente, **D1**/**D13**): `robot_id`,
  `workspace_id NOT NULL` com RLS (**D2**), `cat`, `desc`, `weight` (default 1),
  `progress` (0–100), `status` (enum `Pendente`|`Em Andamento`|`Concluído`|`N/A`),
  `position` (ordem dentro do robô), `lock_version`.
- **Tabela de junção `task_assignees`** por `person_id`, com índice único
  `(task_id, person_id)` e FK composta garantindo mesmo `workspace_id`.
  **BREAKING** em relação ao legado: não existe coluna `resp`, não existe lista de
  nomes, e `"Não Atribuído"` não é gravável.
- **Assistente de criação de robôs em lote** (§2.5): passo 1 com quantidade 1–50
  (clamp) + Aplicação; passo 2 com um nome por robô, placeholder `R01 - Solda`,
  nomes vazios ignorados e duplicatas deduplicadas **dentro da leva**. Cada robô
  nasce com cópia das tarefas-base filtradas pela Aplicação, `progress: 0`,
  `status: "Pendente"`, sem responsável.
- **CRUD de tarefa avulsa**: adicionar, editar descrição, excluir.
- **Lógica do modal de atribuição** (§3.5): substituir o conjunto de responsáveis
  de uma tarefa; cadastrar pessoa nova no workspace que já entra atribuída.
- **Resolução do condicional pendente de §1.4 item 1**: a leitura tolerante
  (`assignees` → senão `resp` ≠ `"Não Atribuído"` → senão vazio) é implementada
  **exclusivamente no importador** (`legacy-data-migration`). O esquema novo
  **não carrega `resp`** e o backend **nunca** grava
  `resp = assignees[0] || "Não Atribuído"`. Ver `design.md` D-RT-2.

### Não-objetivos

- **Máquina de estados progresso↔status (§2.2), modal de avanço (§2.4),
  auto-atribuição (§2.3) e `task_advances`** — pertencem a `progress-advances`.
  Aqui `progress`/`status` são apenas colunas com constraints; nenhum endpoint
  desta capacidade os muta.
- **Cálculo consolidado e `progress_cache` (§2.1, §3.2)** — `progress-rollup`.
  Esta capacidade só garante que a coluna `progress_cache` do robô nasça na
  mesma migration (**D5**) quando `commissioning-hierarchy` a criar.
- **Renderização da tabela, filtro segmentado, agrupamento por categoria, avisos
  de estado incompleto, pulso aos 100%, visual dos modais (§3.5)** —
  `robot-task-table`.
- **Catálogo de templates, enum Aplicação, seed dos 31 padrões, regra de filtro
  `appFilters` e sincronização retroativa (§1.2, §1.3, §2.6)** — `task-catalog`.
  Consumimos a regra de filtro; não a definimos.
- **`Person`, `Membership`, papéis e bootstrap (§1.1, D10/D11)** —
  `workspace-tenancy`. Consumimos `people.id`.
- **Notificações de atribuição (§2.7)** — `in-app-notifications`.
- **Fila offline (§4.3)** — `offline-pwa`. Só garantimos a precondição: uuid
  gerável no cliente e criação idempotente por PK.

## Capabilities

### New Capabilities

- `robot-tasks`: entidade Tarefa, esquema e constraints, CRUD de tarefa avulsa,
  atribuição de responsáveis por `people.id` e leitura por robô.
- `robot-batch-creation`: assistente de dois passos de criação de robôs em lote
  com materialização das tarefas-base filtradas pela Aplicação.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio)

### Impact

- **Depende de** `commissioning-hierarchy` (tabela `robots`, `position`,
  leitura tolerante), `task-catalog` (`task_templates`, enum Aplicação, regra de
  filtro §2.5), `workspace-tenancy` (`people`, `workspace_id`, RLS D2, D10/D11),
  `authorization-policies` (policy declarada por endpoint, D3).
- **É dependência de** `progress-advances` (e por transitividade de
  `progress-rollup`, `robot-task-table`, `my-tasks-view`, `commissioning-report`,
  `offline-pwa`) — está no caminho crítico.
- **Entrega/observabilidade**: a criação em lote de 50 robôs × ~31 tarefas é uma
  única transação de ~1550 inserts; precisa de `insert_all` e de um limite de
  tempo de request monitorado — coordenar com `delivery-and-observability`.
- Novos endpoints Grape sob `namespace :robots` / `namespace :tasks` em
  `backend/app/controllers/api/v1/`, novos services singleton, novas entities,
  novas query keys React Query `['ws', wsId, 'robot', robotId, 'tasks']` (**D9**).
