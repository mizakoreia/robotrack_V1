## ADDED Requirements

### Requirement: PK `uuid` gerável no cliente em toda tabela de domínio

Toda tabela de domínio do RoboTrack SHALL ter chave primária do tipo `uuid` com
`DEFAULT gen_random_uuid()`, e a API SHALL aceitar um `id` fornecido pelo cliente no
corpo do `POST` de criação. Isso vale para `workspaces`, `people`, `memberships`,
`invitations`, `projects`, `cells`, `robots`, `tasks`, `task_templates`,
`task_advances`, `notifications` e `audit_logs` (D1, D13). Nenhuma tabela nova SHALL
usar `bigserial`.

#### Scenario: criação sem id usa o default do banco

- **WHEN** o cliente envia `POST /api/v1/projects` com `{"name": "Linha 7"}` e nenhum `id`
- **THEN** o servidor responde `201` com um `id` no formato UUID gerado por `gen_random_uuid()`
- **AND** a coluna `projects.id` tem tipo `uuid` e default `gen_random_uuid()`

#### Scenario: criação com id do cliente preserva o id

- **WHEN** o cliente envia `POST /api/v1/robots` com
  `{"id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301", "cell_id": "<uuid>", "name": "R01", "application": "Solda Ponto"}`
- **THEN** o servidor responde `201` e o corpo traz exatamente
  `"id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301"`
- **AND** `SELECT id FROM robots WHERE name = 'R01'` devolve esse mesmo valor

#### Scenario: nenhuma tabela nova é bigserial

- **WHEN** um spec de esquema lê `information_schema.columns` para as colunas `id` de
  `projects`, `cells` e `robots`
- **THEN** `data_type` é `uuid` nas três
- **AND** o spec falha se qualquer uma vier como `bigint` ou `integer`

### Requirement: validação de formato do id fornecido

O servidor SHALL rejeitar com `422` qualquer `id` fornecido que não seja um UUID RFC 4122
válido nas versões 1 a 8, e SHALL rejeitar explicitamente o UUID nulo.

#### Scenario: id malformado é rejeitado

- **WHEN** o cliente envia `POST /api/v1/cells` com `{"id": "12345", "project_id": "<uuid>", "name": "Célula A"}`
- **THEN** o servidor responde `422` com mensagem pt-BR identificando o campo `id`
- **AND** nenhuma linha é inserida em `cells`

#### Scenario: UUID nulo é rejeitado

- **WHEN** o cliente envia `POST /api/v1/projects` com
  `{"id": "00000000-0000-0000-0000-000000000000", "name": "Linha 7"}`
- **THEN** o servidor responde `422`
- **AND** a mensagem cita que o id nulo não é aceito, distinta da mensagem de formato inválido

#### Scenario: id com variante inválida é rejeitado

- **WHEN** o cliente envia `POST /api/v1/projects` com
  `{"id": "3f2504e0-4f89-01d3-0a0c-0305e82c3301", "name": "Linha 7"}` (versão `0`, variante `0`)
- **THEN** o servidor responde `422` e não insere linha

### Requirement: replay idempotente de criação

Quando o mesmo `POST` de criação chegar mais de uma vez com o mesmo `id`, mesmo
`workspace_id` de sessão, mesmo escopo pai e mesmo `name`, o servidor SHALL responder
`200` com o recurso já existente e SHALL NOT criar uma segunda linha. Esta é a garantia
que torna a fila de mutations de `offline-pwa` (D7) segura contra reenvio.

#### Scenario: reenvio idêntico devolve 200 e não duplica

- **WHEN** o cliente envia duas vezes `POST /api/v1/robots` com
  `{"id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301", "cell_id": "C1", "name": "R01", "application": "Handling"}`
- **THEN** a primeira responde `201` e a segunda responde `200`
- **AND** `SELECT count(*) FROM robots WHERE id = '3f2504e0-4f89-41d3-9a0c-0305e82c3301'` devolve `1`
- **AND** `updated_at` da linha não mudou entre as duas chamadas

#### Scenario: mesmo id com carga divergente é conflito

- **WHEN** o cliente cria `{"id": "3f25...3301", "cell_id": "C1", "name": "R01"}` e depois
  envia `POST` com `{"id": "3f25...3301", "cell_id": "C1", "name": "R02"}`
- **THEN** o servidor responde `409`
- **AND** o corpo contém o recurso atual (`"name": "R01"`) para o cliente reconciliar
- **AND** a linha continua com `name = 'R01'`

#### Scenario: mesmo id sob pai diferente é conflito

- **WHEN** existe robô `3f25...3301` na célula `C1` e o cliente envia `POST` com
  `{"id": "3f25...3301", "cell_id": "C2", "name": "R01"}`
- **THEN** o servidor responde `409` e o robô permanece em `C1`

### Requirement: id de outro workspace não é revelado

Quando um `POST` fornecer um `id` que já existe em **outro** workspace, o servidor SHALL
responder `404` e SHALL NOT responder `409`, para que a chave primária não funcione como
oráculo de existência entre tenants (§4.1 inv. 1).

#### Scenario: colisão cross-tenant devolve 404

- **WHEN** o workspace `W1` tem o projeto `a1b2c3d4-0000-4000-8000-000000000001` e um
  usuário autenticado no workspace `W2` envia
  `POST /api/v1/projects` com `{"id": "a1b2c3d4-0000-4000-8000-000000000001", "name": "Roubado"}`
- **THEN** o servidor responde `404`
- **AND** o corpo não contém `name`, `workspace_id` nem qualquer campo do projeto de `W1`
- **AND** o projeto de `W1` continua com `name` original

#### Scenario: 404 de colisão é indistinguível de 404 de inexistência

- **WHEN** o mesmo usuário de `W2` faz `GET /api/v1/projects/a1b2c3d4-0000-4000-8000-000000000001`
  e `GET /api/v1/projects/ffffffff-0000-4000-8000-00000000ffff` (id que não existe em lugar nenhum)
- **THEN** as duas respostas têm o mesmo status `404` e o mesmo corpo

### Requirement: `workspace_id` nunca vem do corpo da requisição

O servidor SHALL derivar `workspace_id` exclusivamente do contexto autenticado da
sessão e SHALL ignorar qualquer `workspace_id` presente no corpo do `POST` ou `PATCH`
(D2, §4.1 inv. 2).

#### Scenario: workspace_id do corpo é ignorado

- **WHEN** um usuário cuja sessão está no workspace `W1` envia
  `POST /api/v1/projects` com `{"name": "Linha 7", "workspace_id": "<uuid de W2>"}`
- **THEN** o projeto é criado com `workspace_id = W1`
- **AND** o parâmetro é rejeitado pela declaração de params do Grape ou descartado antes da service
