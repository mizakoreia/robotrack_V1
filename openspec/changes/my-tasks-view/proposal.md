# Minhas Tarefas — lista transversal de tarefas abertas do usuário logado

## Why

A `ESPECIFICACAO.md §3.6` define uma única tela: uma **lista plana e transversal** de
todas as tarefas do workspace em que o usuário logado está entre os responsáveis e cujo
status **não** é `Concluído` nem `N/A`. Colunas: Tarefa · Robô · Célula · Projeto ·
Status · %. Clicar navega até o robô (§3.5).

É a menor capacidade do conjunto e a única com uma **regressão silenciosa embutida no
porte**. No legado (Firestore) o filtro comparava o **nome** do usuário logado com as
strings da lista `responsibles` da tarefa. Por **D10/D11** o alvo abole o endereçamento
por nome: responsável é `people.id`, e o filtro passa a ser `task_assignees.person_id =
<Person do usuário no workspace corrente>`. Isso só funciona se **existir uma linha de
`Person` ligada ao `User`**. No plano anterior nada criava essa linha: nem o bootstrap do
workspace, nem o aceite de convite. Consequência: esta tela retornaria **vazia para todo
mundo, inclusive para o dono do workspace que acabou de se auto-atribuir uma tarefa por
§2.3** — e retornaria vazia sem erro, indistinguível do estado vazio legítimo. Esta
proposta trata a existência da `Person` como **pré-condição verificável e testada**, não
como suposição, e distingue no contrato de API "nenhuma tarefa" de "identidade de
domínio ausente".

Traduções de Firebase feitas aqui: a varredura recursiva de documentos aninhados
(`projects/*/cells/*/robots/*/tasks/*`) que o cliente legado fazia em memória vira **uma
única consulta SQL** com joins, escopada por RLS (D2), paginada e sustentada por índice.

Cobre: §3.6 (integral), §2.2 (semântica de status usada no filtro), §2.3 (auto-atribuição
é o que popula a lista), §3.5 (destino da navegação), §4.1 inv. 1 e 2 (autorização no
servidor, papel vem da membership).

## What Changes

- Novo endpoint Grape `GET /api/v1/workspaces/:workspace_id/my_tasks`, montado em
  `api/v1/base.rb`, servido por `MyTasks::ListService` no contrato singleton
  `ApiResponseHandler`, representado por `Api::Entities::MyTaskRow`.
- Resolução do viewer: `current_user` + workspace corrente → `Person`. A lista é filtrada
  por `person_id`, **nunca** por nome (D10/D11).
- Filtro de status no servidor: apenas `pending` e `in_progress`. `done` e `not_applicable`
  são excluídos (§2.2 / §3.6).
- Escopo de workspace: RLS por `app.current_workspace_id` (D2) **mais** predicado explícito
  `tasks.workspace_id = :ws` na consulta — cinto e suspensório.
- Payload achatado com o caminho completo já denormalizado na resposta (robô, célula,
  projeto), para que a tela não faça N+1 nem hidrate a hierarquia.
- Dois índices dedicados (ver `design.md`), um deles parcial sobre tarefas abertas, e um
  **orçamento de query** verificado em CI contra o dataset de carga compartilhado.
- Tela `MinhasTarefasPage` no shell (`app-shell-navigation`, D9): React Query com a chave
  `['ws', wsId, 'my-tasks']`, tabela responsiva, estado vazio, estado de erro distinto,
  linha clicável que faz deep-link para o robô.
- Spec de regressão que **prova** que um dono recém-criado, que se auto-atribuiu uma
  tarefa, vê a lista preenchida.

### Não-objetivos

- **Não** cria, altera nem remove `Person`, `Membership` ou `task_assignees`. Quem cria
  `Person` é `workspace-tenancy` (bootstrap do dono) e `workspace-invitations` (aceite) —
  aqui são dependências duras, citadas e testadas, não implementadas.
- **Não** implementa a máquina de estados de §2.2 nem o modal de avanço §2.4
  (`progress-advances`). Esta tela é **somente leitura**; não há seletor de status nem
  slider aqui. Registrar avanço exige navegar até o robô.
- **Não** implementa filtros, busca, ordenação escolhida pelo usuário ou agrupamento por
  projeto. §3.6 descreve uma lista plana única.
- **Não** implementa "tarefas de outra pessoa" nem visão de gestor por responsável — isso
  não está na spec.
- **Não** implementa o `progress_cache` nem qualquer consolidação (D5, `progress-rollup`);
  a coluna `%` desta tela é o `progress` **da própria tarefa**, não um agregado.
- **Não** implementa a tela do robô nem o realce da tarefa ao chegar lá
  (`robot-task-table`); esta capacidade só emite o deep-link e fixa seu formato.
- **Não** implementa comportamento offline desta lista (`offline-pwa`).

## Capabilities

### New Capabilities

- `my-tasks-view`: consulta transversal, escopada ao workspace corrente, das tarefas
  abertas atribuídas à `Person` do usuário logado; contrato de API, ordenação
  determinística, paginação, orçamento de desempenho, estados vazio/erro e navegação
  para o robô.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio — nada foi construído ainda.

### Impact

- **Depende de** (Onda ≤ 6, não reimplementar):
  - `progress-advances` — `task_advances`, §2.2, e sobretudo **§2.3 auto-atribuição**,
    que é o mecanismo que coloca a primeira linha nesta lista.
  - `app-shell-navigation` — rota, sidebar, workspace corrente, D9 (React Query).
  - `workspace-tenancy` — `Person`, `Membership`, RLS, **D10** (criação da `Person` do
    dono no bootstrap) e **D11** (sem sentinela `"Não Atribuído"`).
  - `workspace-invitations` — o **segundo** lugar que cria `Person` (aceite de convite,
    casando por e-mail). Um convidado sem `Person` sofre exatamente a mesma falha do dono.
  - `robot-tasks` — `tasks`, `task_assignees`, enum de status, coluna `progress`.
  - `commissioning-hierarchy` — `projects`/`cells`/`robots` e suas `position`, usados na
    ordenação e nas colunas de caminho.
  - `authorization-policies` — D3; o endpoint declara `MyTasksPolicy`, sujeito ao
    route-sweep.
  - `design-system` — Badge de status (rótulo, não seletor), tabular-nums no `%`.
- **É dependência de**: `quality-and-accessibility` (E2E + a11y desta tela),
  `realtime-collaboration` (invalidação da chave `['ws', wsId, 'my-tasks']` ao receber
  evento de tarefa), `offline-pwa` (cache de leitura).
- **Entrega**: nenhuma env var nova, nenhuma fila, nenhum asset externo. Precisa apenas
  que o **dataset de carga** compartilhado (definido em `progress-rollup` e exercitado em
  `quality-and-accessibility`) esteja disponível como factory de RSpec, e que o alerta de
  violação de invariante `membership sem person` chegue ao rastreio de erro de
  `delivery-and-observability`.
- **BREAKING**: nenhum. Não há consumidor prévio.
