## ADDED Requirements

Elenco fixo usado nos cenários deste documento:

- Workspace **WS-A** — dono `Ana` (`role='owner'`), `Bruno` (`role='edit'`),
  `Clara` (`role='view'`).
- Workspace **WS-B** — dono `Diego` (`role='owner'`). Diego não tem membership em WS-A.
- Em WS-A: projeto `P-A1`, célula `C-A1`, robô `R-A1`, tarefa `T-A1`,
  notificação `N-CLARA` (destinatário Clara) e `N-BRUNO` (destinatário Bruno).
- Em WS-B: projeto `P-B1`, robô `R-B1`.

### Requirement: Papel resolvido exclusivamente da associação de membro

O sistema SHALL derivar o papel do requisitante **somente** de
`memberships(workspace_id, person_id).role`, cujo domínio é o enum Postgres
`membership_role ('owner','edit','view')`. Nenhuma policy SHALL ler o índice de
workspaces do usuário, atributos de `users`, claims do JWT ou o RBAC de plano de
cobrança herdado do template para decidir papel (§4.1 inv. 2).

#### Scenario: Índice de UI adulterado não concede papel

- **WHEN** o registro de índice de workspaces de Diego é adulterado para listar WS-A
  com `role: "owner"`, e Diego faz `GET /api/v1/workspaces/WS-A/projects` sem ter
  linha em `memberships` para WS-A
- **THEN** a resposta SHALL ser `404` com corpo `{"error":"not_found"}`, e nenhum
  projeto de WS-A SHALL aparecer no corpo

#### Scenario: Claim de papel no JWT é ignorado

- **WHEN** Clara apresenta um JWT válido cujo payload contém `role: "owner"` e faz
  `DELETE /api/v1/workspaces/WS-A/projects/P-A1`
- **THEN** o sistema SHALL resolver o papel como `view` a partir de `memberships` e
  responder `403 {"error":"forbidden"}`, e `P-A1` SHALL continuar existindo

#### Scenario: Membership removida derruba o acesso no request seguinte

- **WHEN** a membership de Bruno em WS-A é excluída e Bruno reutiliza o mesmo token
  JWT — ainda válido e não expirado — em `GET /api/v1/workspaces/WS-A/projects`
- **THEN** a resposta SHALL ser `404`, sem exigir novo login ou expiração do token

#### Scenario: Enum de papel rejeita valor arbitrário no banco

- **WHEN** um `INSERT INTO memberships (workspace_id, person_id, role)` usa
  `role = 'admin'`
- **THEN** o Postgres SHALL rejeitar por violação de tipo do enum `membership_role`,
  antes de qualquer validação de model

### Requirement: Matriz de permissões da §4.1

O sistema SHALL codificar as 8 linhas da tabela §4.1 como 8 actions nomeadas em
`backend/app/policies/permission_matrix.rb` — `read_workspace`,
`manage_commissioning`, `record_progress`, `manage_catalog`, `create_log`,
`mark_notification_read`, `manage_membership`, `destroy_workspace` — cada uma com a
lista exata de papéis permitidos. Toda policy de recurso SHALL decidir invocando uma
dessas actions e MUST NOT comparar `role` diretamente.

#### Scenario: view lê todo o conteúdo do workspace

- **WHEN** Clara (`view`) faz `GET` em `/projects`, `/projects/P-A1/cells`,
  `/cells/C-A1/robots`, `/robots/R-A1/tasks` e `/audit_logs` de WS-A
- **THEN** todas as 5 respostas SHALL ser `200` com os dados de WS-A

#### Scenario: view não cria nem exclui recurso de comissionamento

- **WHEN** Clara envia `POST /api/v1/workspaces/WS-A/projects`,
  `PATCH .../cells/C-A1`, `DELETE .../robots/R-A1` e `POST .../robots/R-A1/tasks`
- **THEN** as 4 respostas SHALL ser `403 {"error":"forbidden"}` e nenhuma linha SHALL
  ser criada, alterada ou removida

#### Scenario: view não registra avanço, não atribui e não reordena

- **WHEN** Clara envia `POST .../tasks/T-A1/advances` com progresso `45 → 100`,
  `PUT .../tasks/T-A1/assignees` e `PATCH .../projects/reorder`
- **THEN** as 3 respostas SHALL ser `403` e `T-A1` SHALL permanecer com progresso `45`

#### Scenario: view não edita catálogo de tarefas-base nem responsáveis

- **WHEN** Clara envia `POST /api/v1/workspaces/WS-A/task_templates` e
  `POST /api/v1/workspaces/WS-A/people`
- **THEN** ambas SHALL ser `403`

#### Scenario: edit executa toda a linha operacional

- **WHEN** Bruno (`edit`) cria projeto, edita célula, exclui robô, registra avanço
  `45 → 100` em `T-A1`, atribui responsável, reordena e cria tarefa-base
- **THEN** as 7 respostas SHALL estar na faixa `2xx`

#### Scenario: edit não gerencia membros

- **WHEN** Bruno envia `POST /api/v1/workspaces/WS-A/invitations`,
  `PATCH /api/v1/workspaces/WS-A/memberships/<clara>` com `role: "edit"` e
  `DELETE /api/v1/workspaces/WS-A/memberships/<clara>`
- **THEN** as 3 respostas SHALL ser `403` e o papel de Clara SHALL continuar `view`

#### Scenario: edit não destrói workspace nem faz reset de fábrica

- **WHEN** Bruno envia `DELETE /api/v1/workspaces/WS-A` e
  `POST /api/v1/workspaces/WS-A/factory_reset`
- **THEN** ambas SHALL ser `403` e a contagem de projetos de WS-A SHALL permanecer
  inalterada

#### Scenario: owner executa as 8 actions

- **WHEN** Ana exercita uma requisição representativa de cada uma das 8 actions da
  matriz
- **THEN** nenhuma das 8 SHALL responder `403`

#### Scenario: matriz não consulta plano de cobrança

- **WHEN** o usuário de Bruno tem o RBAC de plano herdado do template sem nenhuma
  permissão concedida, e Bruno cria um projeto em WS-A
- **THEN** a resposta SHALL ser `201` — o papel de workspace é o único eixo de decisão

### Requirement: Gate de autorização anterior ao service

O sistema SHALL avaliar a policy declarada na rota dentro do `before` de
`Api::Root`, depois da autenticação e antes de qualquer service ser invocado. Nenhum
service de domínio SHALL ser executado numa requisição que será negada (§4.1 inv. 1).

#### Scenario: Negação não chega ao service

- **WHEN** Clara envia `DELETE .../projects/P-A1` e o service `ProjectService` está
  instrumentado para registrar invocação
- **THEN** a resposta SHALL ser `403` e `ProjectService` SHALL registrar zero invocações

#### Scenario: Rota sem policy declarada falha fechada

- **WHEN** um endpoint Grape é montado sem `route_setting :policy` e sem entrada em
  `config/authorization/public_routes.yml`, e recebe uma requisição autenticada em
  ambiente `test`
- **THEN** o sistema SHALL levantar `Authorization::UndeclaredRouteError` e MUST NOT
  responder `200`

#### Scenario: Rota sem policy em produção responde 500, nunca 200

- **WHEN** a mesma rota não declarada recebe requisição com `RAILS_ENV=production`
- **THEN** a resposta SHALL ser `500`, o rastreio de erro SHALL receber o evento, e o
  corpo MUST NOT conter dado de domínio

#### Scenario: X-Skip-Auth não contorna a autorização

- **WHEN** Diego envia `GET /api/v1/workspaces/WS-A/projects` com o header
  `X-Skip-Auth: 1`
- **THEN** a resposta SHALL ser `401` ou `404` e MUST NOT conter projetos de WS-A

### Requirement: Recurso de outro tenant responde 404

O sistema SHALL responder `404 {"error":"not_found"}` — indistinguível de id
inexistente — para qualquer requisição que enderece recurso pertencente a workspace
diferente do contexto. O `403` SHALL ficar reservado a recurso do próprio workspace
com papel insuficiente.

#### Scenario: Owner de outro workspace não enxerga projeto alheio

- **WHEN** Diego (owner de WS-B) faz `GET /api/v1/workspaces/WS-A/projects/P-A1`
- **THEN** a resposta SHALL ser `404`, idêntica em corpo e status à resposta para um
  UUID que não existe em tabela alguma

#### Scenario: Id cruzado dentro do próprio workspace também é 404

- **WHEN** Ana faz `GET /api/v1/workspaces/WS-A/robots/R-B1`, usando seu próprio
  workspace no path e um id de robô de WS-B
- **THEN** a resposta SHALL ser `404` e MUST NOT vazar nome ou qualquer campo de `R-B1`

#### Scenario: Escrita cruzada não persiste

- **WHEN** Diego envia `POST /api/v1/workspaces/WS-A/projects/P-A1/cells` com corpo
  válido
- **THEN** a resposta SHALL ser `404` e a contagem de células de `P-A1` SHALL
  permanecer inalterada

#### Scenario: RLS sozinha já nega, sem a policy

- **WHEN** a avaliação de policy é desabilitada em ambiente de teste e Diego repete
  `GET /api/v1/workspaces/WS-A/projects/P-A1`
- **THEN** a resposta SHALL ser `404`, provando que o isolamento não depende da camada
  de aplicação

### Requirement: Notificação — única mutação permitida

O sistema SHALL permitir a um membro de qualquer papel exatamente uma mutação de
notificação: marcar como lida a notificação **cujo destinatário é ele próprio**.
Nenhuma outra coluna de `notifications` SHALL poder mudar após o `INSERT`, para
nenhum papel, **inclusive `owner`** (§4.1 inv. 4; porte de
`affectedKeys().hasOnly(['read'])`, `firestore.rules` L61-62).

#### Scenario: view marca a própria notificação como lida

- **WHEN** Clara envia `PATCH /api/v1/workspaces/WS-A/notifications/N-CLARA` com
  `{"read": true}`
- **THEN** a resposta SHALL ser `200` e `N-CLARA.read` SHALL passar a `true`

#### Scenario: view não marca notificação de outra pessoa

- **WHEN** Clara envia `PATCH .../notifications/N-BRUNO` com `{"read": true}`
- **THEN** a resposta SHALL ser `403` e `N-BRUNO.read` SHALL permanecer `false`

#### Scenario: mudar outro campo junto com read é rejeitado

- **WHEN** Clara envia `PATCH .../notifications/N-CLARA` com
  `{"read": true, "message": "invadido"}`
- **THEN** a resposta SHALL ser `422`, `N-CLARA.message` SHALL permanecer inalterado e
  `N-CLARA.read` SHALL permanecer `false` — a requisição é rejeitada inteira, não
  parcialmente aplicada

#### Scenario: owner também não altera o corpo da notificação

- **WHEN** Ana (`owner`) executa no console
  `Notification.find(N_CLARA).update_column(:message, "editado")`
- **THEN** o trigger de banco SHALL levantar exceção e a mensagem SHALL permanecer a
  original

#### Scenario: view não cria notificação

- **WHEN** Clara envia `POST /api/v1/workspaces/WS-A/notifications`
- **THEN** a resposta SHALL ser `403` (§4.1, linha "criar log / notificação")

### Requirement: Dono do workspace é imutável

O sistema SHALL impedir alteração de `workspaces.owner_person_id` por qualquer
caminho — API, console ou SQL direto — e SHALL garantir exatamente uma membership com
`role='owner'` por workspace (§4.1 inv. 5). Nenhuma action da matriz SHALL
corresponder a transferência de propriedade.

#### Scenario: Owner não transfere a própria propriedade pela API

- **WHEN** Ana envia `PATCH /api/v1/workspaces/WS-A` com
  `{"owner_person_id": "<bruno>"}`
- **THEN** a resposta SHALL ser `422` ou o campo SHALL ser ignorado, e
  `WS-A.owner_person_id` SHALL continuar apontando para Ana

#### Scenario: UPDATE direto no banco é bloqueado por trigger

- **WHEN** `UPDATE workspaces SET owner_person_id = '<bruno>' WHERE id = 'WS-A'` é
  executado diretamente no Postgres
- **THEN** o trigger SHALL levantar exceção e a transação SHALL abortar

#### Scenario: Promover segundo dono viola índice único

- **WHEN** `UPDATE memberships SET role = 'owner'` é aplicado à membership de Bruno em
  WS-A
- **THEN** o índice único parcial `(workspace_id) WHERE role = 'owner'` SHALL rejeitar,
  deixando WS-A com um único dono

#### Scenario: Owner não remove a própria membership

- **WHEN** Ana envia `DELETE /api/v1/workspaces/WS-A/memberships/<ana>`
- **THEN** a resposta SHALL ser `422` e WS-A SHALL continuar com dono

### Requirement: Log de auditoria é append-only para todos

O sistema SHALL expor apenas leitura e criação de `audit_logs`. Nenhuma rota de
atualização ou exclusão de log SHALL existir, e `AuditLogPolicy` MUST NOT definir
predicados de escrita além de criação (§4.1 inv. 3; `firestore.rules` L49
`allow update, delete: if false`).

#### Scenario: Owner não edita log de auditoria

- **WHEN** Ana envia `PATCH /api/v1/workspaces/WS-A/audit_logs/<id>` com
  `{"message": "reescrito"}`
- **THEN** a resposta SHALL ser `404` ou `405` — a rota não existe — e a mensagem
  original SHALL permanecer

#### Scenario: Owner não exclui log de auditoria

- **WHEN** Ana envia `DELETE /api/v1/workspaces/WS-A/audit_logs/<id>`
- **THEN** a resposta SHALL ser `404` ou `405` e a contagem de logs SHALL permanecer

#### Scenario: view lê o log mas não cria

- **WHEN** Clara faz `GET .../audit_logs` e depois `POST .../audit_logs`
- **THEN** a primeira SHALL ser `200` e a segunda SHALL ser `403`

### Requirement: Autorização de convites e de membros

O sistema SHALL restringir criação, revogação e alteração de convite e de membership
ao papel `owner`, e SHALL forçar o `workspace_id` do convite a ser o do contexto
autenticado, com papel do convite limitado a `view` ou `edit` (§4.1 inv. 7;
`firestore.rules` L72-77). A atomicidade do **consumo** do convite é responsabilidade
de `workspace-invitations`; aqui vale o plano de autorização.

#### Scenario: workspace_id do corpo do convite é ignorado

- **WHEN** Ana (owner de WS-A) envia `POST /api/v1/workspaces/WS-A/invitations` com
  corpo `{"workspace_id": "WS-B", "email": "x@ex.com", "role": "edit"}`
- **THEN** o convite criado SHALL apontar para WS-A, nunca WS-B

#### Scenario: Convite com papel owner é rejeitado

- **WHEN** Ana envia `POST .../invitations` com `{"role": "owner"}`
- **THEN** a resposta SHALL ser `422` e o `CHECK role IN ('view','edit')` da tabela
  SHALL impedir a linha mesmo se a validação de model for contornada

#### Scenario: edit não lista nem revoga convites alheios

- **WHEN** Bruno faz `GET /api/v1/workspaces/WS-A/invitations` e
  `DELETE .../invitations/<id>`
- **THEN** ambas SHALL ser `403`

#### Scenario: Owner de WS-B não revoga convite de WS-A

- **WHEN** Diego envia `DELETE /api/v1/workspaces/WS-A/invitations/<id de WS-A>`
- **THEN** a resposta SHALL ser `404` e o convite SHALL continuar ativo

### Requirement: Contrato de resposta de negação

O sistema SHALL responder negações com corpo mínimo e sem detalhe de política:
`401 {"error":"unauthorized"}` sem credencial válida, `403 {"error":"forbidden"}`
para papel insuficiente e `404 {"error":"not_found"}` para recurso fora do tenant.
O corpo MUST NOT conter nome de policy, action, papel exigido ou papel efetivo.

#### Scenario: 403 não revela o papel exigido

- **WHEN** Clara recebe `403` ao tentar `DELETE .../projects/P-A1`
- **THEN** o corpo SHALL ter exatamente a chave `error` e MUST NOT conter as strings
  `"owner"`, `"edit"`, `"ProjectPolicy"` ou `"manage_commissioning"`

#### Scenario: 404 de tenant é indistinguível de id inexistente

- **WHEN** Diego pede `P-A1` (existe, de outro tenant) e depois um UUID aleatório
- **THEN** as duas respostas SHALL ter status, corpo e headers idênticos
