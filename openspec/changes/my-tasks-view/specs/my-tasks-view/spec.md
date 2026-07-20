# Spec — `my-tasks-view`

## ADDED Requirements

### Requirement: Identidade do responsável por `person_id`

O sistema SHALL filtrar a lista de Minhas Tarefas exclusivamente por
`task_assignees.person_id`, onde a `person_id` é a da `Person` do usuário autenticado no
workspace corrente. O sistema MUST NOT usar o nome de exibição do usuário, o e-mail, o
`user_id` ou qualquer string em nenhum predicado de filtro desta lista.

#### Scenario: Tarefa atribuída por id aparece mesmo com nome divergente

- **WHEN** o usuário autenticado `ana@ex.com` tem `Person(id: P1, name: "Ana Souza")` no
  workspace `W1`, seu `User#display_name` é alterado para `"Ana S."`, e existe a tarefa
  `T1` ("Backup do programa", `status: in_progress`, `progress: 45`) com
  `task_assignees = [P1]`
- **THEN** `GET /api/v1/workspaces/W1/my_tasks` SHALL retornar `200` com exatamente 1
  linha, cujo `task_id` é `T1`

#### Scenario: Homônimo em outra Person não vaza tarefas

- **WHEN** o workspace `W1` tem `Person(id: P1, name: "João Silva", user_id: U1)` e
  `Person(id: P2, name: "João Silva", user_id: U2)`, e a tarefa `T2`
  (`status: in_progress`) tem `task_assignees = [P2]`
- **THEN** a requisição autenticada como `U1` SHALL retornar `200` com `0` linhas, e `T2`
  MUST NOT aparecer

#### Scenario: Esquema não admite responsável como texto

- **WHEN** o spec de esquema inspeciona as colunas de `tasks` e de `task_assignees`
- **THEN** nenhuma coluna de tipo `text`/`varchar` cujo nome contenha `responsible`,
  `assignee_name` ou `responsavel` SHALL existir, e o spec MUST falhar se alguma aparecer

---

### Requirement: Filtro de status — apenas tarefas abertas

O sistema SHALL retornar apenas tarefas cujo `status` seja `pending` ou `in_progress`.
Tarefas com `status` `done` ou `not_applicable` MUST NOT ser retornadas. O filtro SHALL
ser aplicado no servidor, na cláusula `WHERE` da consulta, nunca no cliente.

#### Scenario: Tarefa em andamento atribuída a mim aparece

- **WHEN** `T1` ("Ajuste de TCP", `status: in_progress`, `progress: 45`) tem
  `task_assignees = [P1]` e o viewer é a `Person` `P1`
- **THEN** a resposta SHALL conter uma linha com `task_id = T1`, `status = "in_progress"` e
  `progress = 45`

#### Scenario: A mesma tarefa levada a Concluído some da lista

- **WHEN** a tarefa `T1` do cenário anterior recebe um avanço de `45 → 100`, o que por
  §2.2 a leva a `status: done`, e a lista é consultada novamente
- **THEN** a resposta SHALL conter `0` linhas e `T1` MUST NOT aparecer

#### Scenario: Tarefa em N/A atribuída a mim não aparece

- **WHEN** `T3` ("Solda a ponto — não aplicável a este robô", `status: not_applicable`,
  `progress: 0`) tem `task_assignees = [P1]` e o viewer é `P1`
- **THEN** `T3` MUST NOT aparecer na resposta

#### Scenario: Tarefa pendente com progresso 0 aparece

- **WHEN** `T4` ("Calibração de garra", `status: pending`, `progress: 0`) tem
  `task_assignees = [P1]`
- **THEN** `T4` SHALL aparecer na resposta com `progress = 0`

#### Scenario: O enum de status permanece com exatamente 4 valores

- **WHEN** o spec de esquema lê os valores do enum de `tasks.status`
- **THEN** o conjunto SHALL ser exatamente
  `{pending, in_progress, done, not_applicable}`, e o spec MUST falhar caso um quinto
  valor seja adicionado sem revisar o índice parcial `idx_tasks_open_ws`

---

### Requirement: Escopo ao workspace corrente

O sistema SHALL restringir a lista às tarefas do workspace corrente da requisição. O
isolamento SHALL ser garantido por RLS sobre `app.current_workspace_id` (D2), e o service
SHALL adicionalmente declarar `task_assignees.workspace_id = :ws` no predicado.

#### Scenario: Tarefa de outro workspace não aparece

- **WHEN** o usuário `U1` tem `Person(P1)` no workspace `W1` e `Person(P9)` no workspace
  `W9`, a tarefa `T9` (`status: in_progress`) pertence a `W9` e tem
  `task_assignees = [P9]`, e a requisição é `GET /api/v1/workspaces/W1/my_tasks`
- **THEN** a resposta SHALL conter `0` linhas e `T9` MUST NOT aparecer

#### Scenario: A mesma conta vê listas diferentes por workspace

- **WHEN** `U1` tem 3 tarefas abertas atribuídas a `P1` em `W1` e 1 tarefa aberta
  atribuída a `P9` em `W9`
- **THEN** `GET /api/v1/workspaces/W1/my_tasks` SHALL retornar `3` linhas e
  `GET /api/v1/workspaces/W9/my_tasks` SHALL retornar `1` linha

#### Scenario: RLS sozinha impede vazamento entre tenants

- **WHEN** o predicado explícito `task_assignees.workspace_id = :ws` é removido do service
  por stub no spec, e `U1` (membro de `W1`) consulta com `app.current_workspace_id = W1`
- **THEN** nenhuma linha de `W9` SHALL ser retornada

#### Scenario: Não-membro do workspace é recusado

- **WHEN** o usuário `U7`, autenticado e sem `Membership` em `W1`, chama
  `GET /api/v1/workspaces/W1/my_tasks`
- **THEN** o sistema SHALL responder `403` e MUST NOT retornar corpo com linhas

#### Scenario: Requisição sem autenticação é recusada

- **WHEN** `GET /api/v1/workspaces/W1/my_tasks` é chamado sem header `Authorization` e com
  header `X-Skip-Auth: 1`
- **THEN** o sistema SHALL responder `401`

---

### Requirement: Tarefas de outras pessoas nunca aparecem

O sistema SHALL retornar apenas tarefas em que o viewer é responsável. O viewer SHALL ser
derivado exclusivamente do token de autenticação; o endpoint MUST NOT aceitar nenhum
parâmetro que selecione outra pessoa.

#### Scenario: Tarefa atribuída a outra pessoa não aparece

- **WHEN** `T5` ("Teste de rota 12", `status: in_progress`) tem `task_assignees = [P2]`,
  `P2` é outra pessoa do mesmo workspace `W1`, e o viewer é `P1`
- **THEN** `T5` MUST NOT aparecer na resposta

#### Scenario: Tarefa com múltiplos responsáveis incluindo eu aparece uma única vez

- **WHEN** `T6` (`status: in_progress`) tem `task_assignees = [P1, P2, P3]` e o viewer é
  `P1`
- **THEN** a resposta SHALL conter exatamente `1` linha para `T6`, sem duplicação por
  responsável

#### Scenario: Parâmetro `person_id` é ignorado ou recusado

- **WHEN** o viewer `P1` chama `GET /api/v1/workspaces/W1/my_tasks?person_id=P2`
- **THEN** a resposta SHALL conter apenas tarefas de `P1`, e nenhuma tarefa exclusiva de
  `P2` SHALL aparecer

#### Scenario: Membro com papel `view` consegue ler a própria lista

- **WHEN** `U4` tem `Membership(role: "view")` em `W1` e `Person(P4)` com 2 tarefas
  abertas atribuídas
- **THEN** a resposta SHALL ser `200` com `2` linhas (§4.1 inv. 4 restringe mutação, não
  leitura)

---

### Requirement: A `Person` do viewer deve existir; sua ausência é erro explícito

O sistema SHALL resolver o viewer por `Person.find_by(workspace_id:, user_id:)`. Quando o
usuário é membro do workspace mas nenhuma `Person` correspondente existe, o sistema SHALL
responder `409` com código `person_missing` e registrar a violação no rastreio de erro. O
sistema MUST NOT responder `200` com lista vazia nesse caso, e MUST NOT criar uma `Person`
sob demanda.

#### Scenario: Dono recém-criado que se auto-atribuiu uma tarefa vê a lista preenchida

- **WHEN** um usuário novo `dono@ex.com` faz o primeiro login, o bootstrap real de
  `workspace-tenancy` cria o workspace `W1` e a `Person` do dono (D10), o dono cria
  projeto/célula/robô/tarefa e registra um avanço de `0 → 20` numa tarefa **sem
  responsável**, o que por §2.3 o auto-atribui
- **THEN** `GET /api/v1/workspaces/W1/my_tasks` SHALL retornar `200` com exatamente `1`
  linha, e o spec MUST NOT criar a `Person` diretamente por factory — ela SHALL vir do
  bootstrap real

#### Scenario: Convidado que aceitou convite vê a lista preenchida

- **WHEN** `convidado@ex.com` aceita um convite para `W1` pelo fluxo real de
  `workspace-invitations` (que cria ou casa a `Person` por e-mail, D10), e uma tarefa
  aberta é atribuída a essa `Person`
- **THEN** `GET /api/v1/workspaces/W1/my_tasks` SHALL retornar `200` com `1` linha, e o
  spec MUST NOT criar a `Person` por factory

#### Scenario: Membro sem Person recebe 409, não lista vazia

- **WHEN** uma `Membership` de `U5` em `W1` existe com `person_id` apontando para uma
  `Person` posteriormente removida por dado legado, de modo que
  `Person.find_by(workspace_id: W1, user_id: U5)` retorna `nil`
- **THEN** o sistema SHALL responder `409` com `code = "person_missing"`, SHALL registrar
  o evento no rastreio de erro, e MUST NOT responder `200`

#### Scenario: A requisição não cria Person

- **WHEN** a condição do cenário anterior ocorre e a requisição é repetida 3 vezes
- **THEN** `people.count` no workspace `W1` SHALL permanecer inalterada nas 3 requisições

#### Scenario: O banco impede o estado de membro sem Person

- **WHEN** um `INSERT` em `memberships` é tentado com `person_id = NULL`
- **THEN** o Postgres SHALL rejeitar por `NOT NULL`, e um `INSERT` com `person_id`
  inexistente SHALL ser rejeitado pela FK `references people(id)`

---

### Requirement: Pessoa sem conta de usuário nunca acessa esta tela

O sistema SHALL permitir que uma `Person` com `user_id` nulo seja responsável por tarefas
(D10). Essa pessoa MUST NOT ter acesso à lista de Minhas Tarefas, por não possuir `User` e
portanto não autenticar. Uma tarefa cujos únicos responsáveis têm `user_id` nulo SHALL NOT
aparecer na lista de nenhum usuário.

#### Scenario: Tarefa do operador sem conta não vaza para o dono

- **WHEN** `Person(P8, name: "Carlos Operador", user_id: NULL)` é o único responsável pela
  tarefa `T8` (`status: in_progress`) em `W1`, e o dono `P1` consulta a lista
- **THEN** `T8` MUST NOT aparecer na resposta do dono

#### Scenario: Atribuir a pessoa sem conta continua sendo permitido

- **WHEN** a tarefa `T8` é atribuída a `Person(P8)` com `user_id = NULL`
- **THEN** a atribuição SHALL ser aceita e `T8` SHALL aparecer normalmente na tabela do
  robô (§3.5), com o nome de `P8` nos chips de responsáveis

---

### Requirement: Colunas, payload e navegação

O sistema SHALL retornar, para cada linha, os dados suficientes para renderizar as colunas
de §3.6 — Tarefa, Robô, Célula, Projeto, Status, `%` — sem nenhuma requisição adicional.
Cada linha SHALL carregar `task_id`, `robot_id`, `cell_id` e `project_id`. Clicar em uma
linha SHALL navegar para `/ws/:wsId/robots/:robotId?task=:taskId`.

#### Scenario: Payload contém o caminho completo achatado

- **WHEN** a tarefa `T1` ("Ajuste de TCP") pertence ao robô `"R-07"`, na célula
  `"Célula 3"`, no projeto `"Linha de Solda A"`, com `status: in_progress` e
  `progress: 45`
- **THEN** a linha retornada SHALL conter `description = "Ajuste de TCP"`,
  `robot_name = "R-07"`, `cell_name = "Célula 3"`, `project_name = "Linha de Solda A"`,
  `status = "in_progress"`, `progress = 45`, e os quatro ids correspondentes

#### Scenario: A lista é servida por uma única consulta SQL

- **WHEN** a requisição é feita com 50 linhas no resultado e a contagem de queries é
  instrumentada
- **THEN** o número de consultas SQL de leitura de domínio SHALL ser exatamente `1`

#### Scenario: Clique navega ao robô com a tarefa no query string

- **WHEN** o usuário clica na linha de `T1` (robô `R7`, workspace `W1`)
- **THEN** o roteador SHALL navegar para `/ws/W1/robots/R7?task=T1`

#### Scenario: A linha é navegável por teclado

- **WHEN** o usuário navega por `Tab` até a linha de `T1` e pressiona `Enter`
- **THEN** a navegação SHALL ocorrer do mesmo modo que no clique, e o elemento focado
  SHALL ser um `<a>` com `href` real (permitindo "abrir em nova aba")

#### Scenario: A tela é somente leitura

- **WHEN** a lista é renderizada com 3 linhas
- **THEN** nenhum seletor de status, slider de progresso ou botão de avanço SHALL existir
  na tela; o `%` SHALL ser renderizado como texto com `tabular-nums` e o status como
  **badge** (rótulo), nunca como controle

---

### Requirement: Ordenação determinística e paginação

O sistema SHALL ordenar as linhas por caminho hierárquico —
`projects.position, projects.id, cells.position, cells.id, robots.position, robots.id,
tasks.position, tasks.id` — produzindo ordem total e estável. O sistema SHALL paginar com
`page` e `per_page` (padrão `50`, teto `200`) e SHALL emitir os headers de paginação do
helper existente.

#### Scenario: Ordem segue o caminho hierárquico

- **WHEN** o viewer tem tarefas abertas no projeto `"A"` (`position: 1`) e no projeto
  `"B"` (`position: 2`), e dentro de `"A"` nas células de `position` `1` e `2`
- **THEN** todas as linhas de `"A"` SHALL preceder as de `"B"`, e dentro de `"A"` as
  linhas da célula `1` SHALL preceder as da célula `2`

#### Scenario: Empate de position é desempatado por id

- **WHEN** duas células do mesmo projeto têm `position = 1` e a lista é requisitada 5
  vezes
- **THEN** a ordem das linhas SHALL ser idêntica nas 5 respostas, ordenada por `cells.id`
  crescente no empate

#### Scenario: Paginação não repete nem omite linhas

- **WHEN** o viewer tem `120` tarefas abertas e as páginas `1`, `2` e `3` são requisitadas
  com `per_page = 50`
- **THEN** a união das três páginas SHALL conter exatamente `120` `task_id` distintos, com
  `50`, `50` e `20` linhas respectivamente

#### Scenario: `per_page` acima do teto é limitado

- **WHEN** a requisição usa `per_page = 1000`
- **THEN** o sistema SHALL retornar no máximo `200` linhas e SHALL refletir `200` nos
  headers de paginação

---

### Requirement: Estados vazio e de erro são visualmente distintos

O sistema SHALL renderizar três estados mutuamente exclusivos e distinguíveis: lista vazia
legítima (`200` com `[]`), identidade ausente (`409 person_missing`) e falha de
rede/servidor. O estado vazio MUST NOT ser usado para representar erro.

#### Scenario: Estado vazio legítimo nomeia a regra de exclusão

- **WHEN** o viewer `P1` não tem nenhuma tarefa aberta atribuída e a resposta é `200` com
  `0` linhas
- **THEN** a tela SHALL exibir o título "Nenhuma tarefa aberta atribuída a você" e o texto
  "Tarefas concluídas e marcadas como N/A não aparecem aqui.", com uma ação secundária
  "Ir para Visão Geral"

#### Scenario: Estado de identidade ausente não se parece com o estado vazio

- **WHEN** a resposta é `409` com `code = "person_missing"`
- **THEN** a tela SHALL exibir "Não foi possível identificar seu cadastro neste
  workspace." com ação "Tentar novamente", e MUST NOT exibir o texto do estado vazio

#### Scenario: Falha de rede exibe estado de erro com retry

- **WHEN** a requisição falha com `503`
- **THEN** a tela SHALL exibir o estado de erro do shell com ação "Tentar novamente", e
  MUST NOT exibir o texto do estado vazio

#### Scenario: Todas as strings da tela são centralizadas

- **WHEN** o spec varre o componente da tela em busca de literais de texto pt-BR
- **THEN** nenhum literal de UI SHALL estar embutido no componente; todos SHALL vir do
  módulo único de strings (D14)

---

### Requirement: Orçamento de desempenho sustentado por índice

O sistema SHALL sustentar a consulta com o índice
`idx_task_assignees_ws_person (workspace_id, person_id) INCLUDE (task_id)` e o índice
parcial `idx_tasks_open_ws (workspace_id, id) WHERE status IN ('pending','in_progress')`.
Contra o dataset de carga compartilhado, a consulta da primeira página SHALL executar em
menos de `120 ms` no p95 e MUST NOT produzir sequential scan em `tasks`.

#### Scenario: Plano de execução usa o índice de responsáveis

- **WHEN** `EXPLAIN (ANALYZE, BUFFERS)` é executado sobre a consulta no dataset de carga
  (10 projetos × 8 células × 12 robôs × 30 tarefas ≈ 28.800 tarefas; viewer com 1.500
  atribuições, ~600 abertas)
- **THEN** o plano SHALL usar `idx_task_assignees_ws_person` como driver e MUST NOT conter
  `Seq Scan on tasks`

#### Scenario: p95 dentro do orçamento

- **WHEN** a primeira página (`per_page = 50`) é consultada 100 vezes no dataset de carga
- **THEN** o p95 SHALL ser inferior a `120 ms`, e o spec MUST falhar acima disso

#### Scenario: Índices são criados por migration reversível

- **WHEN** a migration desta capacidade é revertida com `rails db:rollback`
- **THEN** os dois índices SHALL ser removidos, nenhuma tabela ou linha SHALL ser afetada,
  e reaplicar a migration SHALL ser idempotente (`IF NOT EXISTS`)

---

### Requirement: Atualização da lista após mutação

O sistema SHALL expor a lista sob a chave de React Query `['ws', wsId, 'my-tasks']` (D9) e
SHALL invalidá-la ao receber, pelo `WorkspaceChannel` (D6), evento de mudança de tarefa ou
de atribuição no workspace corrente.

#### Scenario: Concluir a tarefa em outra aba a remove desta lista

- **WHEN** a lista está aberta com `T1` visível e um evento `task.updated` para `T1` com
  `status: done` chega pelo `WorkspaceChannel`
- **THEN** a chave `['ws', W1, 'my-tasks']` SHALL ser invalidada e, após o refetch, `T1`
  MUST NOT aparecer

#### Scenario: Ser atribuído a uma tarefa a insere na lista

- **WHEN** outro usuário atribui `T7` (`status: in_progress`) à `Person` `P1` e o evento
  `task_assignees.changed` chega
- **THEN** após a invalidação e o refetch, `T7` SHALL aparecer na lista de `P1`

#### Scenario: Trocar de workspace não reaproveita o resultado anterior

- **WHEN** o usuário está em `W1` com 3 linhas e troca para `W9` pelo seletor de workspace
- **THEN** a tela SHALL consultar `['ws', W9, 'my-tasks']` e MUST NOT exibir, em nenhum
  quadro, as linhas de `W1`
