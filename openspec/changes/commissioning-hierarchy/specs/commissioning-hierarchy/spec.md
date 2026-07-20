## ADDED Requirements

### Requirement: esquema relacional de projeto, célula e robô

O sistema SHALL persistir a hierarquia de §1.1 em três tabelas relacionais —
`projects`, `cells`, `robots` — substituindo os arrays aninhados do legado. Cada tabela
SHALL ter: `id uuid` PK, `workspace_id uuid NOT NULL`, `name`, `position integer NOT NULL`,
`progress_cache jsonb NOT NULL DEFAULT '{}'`, `progress_cached_at timestamptz`,
`lock_version integer NOT NULL DEFAULT 0`, `updated_by_person_id uuid`, `created_at` e
`updated_at`. `cells` SHALL ter `project_id`; `robots` SHALL ter `cell_id` e
`application`.

#### Scenario: as três tabelas expõem os campos obrigatórios

- **WHEN** um spec de esquema inspeciona `projects`, `cells` e `robots`
- **THEN** as três têm `workspace_id` com `is_nullable = 'NO'`
- **AND** as três têm `lock_version integer NOT NULL DEFAULT 0`
- **AND** as três têm `updated_by_person_id` e `updated_at` — não só `projects`, ao
  contrário do legado, onde `_updatedBy`/`_updatedAt` existiam apenas no projeto

#### Scenario: `progress_cache` existe desde a migration de criação

- **WHEN** a migration que cria `robots` é aplicada numa base limpa
- **THEN** `robots.progress_cache` já existe, é `jsonb`, `NOT NULL`, default `'{}'::jsonb`
- **AND** nenhuma migration posterior de `progress-rollup` precisa de `ALTER TABLE` para
  adicioná-la (D5)

#### Scenario: nome em branco é rejeitado pelo banco

- **WHEN** um `INSERT` direto tenta `name = '   '` em `cells`
- **THEN** o Postgres rejeita por violação de `CHECK (length(btrim(name)) BETWEEN 1 AND 120)`
- **AND** a API responde `422` ao mesmo payload, sem depender do model para a garantia

#### Scenario: nome com 121 caracteres é rejeitado

- **WHEN** o cliente cria um projeto com `name` de 121 caracteres
- **THEN** o servidor responde `422` e nenhuma linha é inserida

### Requirement: `application` do robô é enum fechado de §1.2

O sistema SHALL restringir `robots.application` aos seis valores literais de §1.2 —
`Misto / Geral`, `Solda Ponto`, `Solda MIG`, `Handling`, `Sealing`, `Outros` — por
`CHECK` constraint, com default `Misto / Geral`.

#### Scenario: aplicação fora do enum é rejeitada pelo banco

- **WHEN** um `INSERT` direto tenta `application = 'Pintura'` em `robots`
- **THEN** o Postgres rejeita por violação de `CHECK`
- **AND** a API responde `422` listando os seis valores aceitos

#### Scenario: robô criado sem aplicação assume `Misto / Geral`

- **WHEN** o cliente envia `POST /api/v1/robots` com `{"cell_id": "C1", "name": "R09"}` sem `application`
- **THEN** o robô é criado com `application = 'Misto / Geral'`

### Requirement: tenancy garantida por constraint e RLS

O sistema SHALL impedir, no nível do banco, que uma célula pertença a um projeto de
outro workspace ou que um robô pertença a uma célula de outro workspace, por meio de FK
composta `(parent_id, workspace_id)`. O sistema SHALL habilitar `ROW LEVEL SECURITY` com
`FORCE` nas três tabelas, filtrando por `current_setting('app.current_workspace_id')`
(D2, §4.1 inv. 1).

#### Scenario: célula com workspace divergente do projeto é impossível

- **WHEN** um `UPDATE` de console tenta setar `cells.workspace_id = W2` numa célula cujo
  projeto tem `workspace_id = W1`
- **THEN** o Postgres rejeita por violação da FK composta
  `(project_id, workspace_id) REFERENCES projects (id, workspace_id)`

#### Scenario: sessão sem workspace corrente não enxerga nenhuma linha

- **WHEN** uma conexão executa `SELECT count(*) FROM projects` sem ter setado
  `app.current_workspace_id`
- **THEN** o resultado é `0`, mesmo havendo 12 projetos na tabela (fail-closed)

#### Scenario: usuário de outro workspace não lê nem escreve

- **WHEN** um usuário autenticado no workspace `W2` faz
  `GET /api/v1/projects/<uuid de projeto de W1>` e depois
  `PATCH` no mesmo id com `{"name": "Renomeado"}`
- **THEN** as duas requisições respondem `404`
- **AND** o projeto de `W1` mantém o nome original
- **AND** nenhum campo de `W1` aparece em qualquer corpo de resposta

#### Scenario: RLS vale também para o dono da tabela

- **WHEN** o spec verifica `pg_class.relforcerowsecurity` para `projects`, `cells`, `robots`
- **THEN** as três retornam `true`, de modo que o role de migration não contorne a política

### Requirement: CRUD de projeto, célula e robô

O sistema SHALL expor criação, renomeação e exclusão dos três níveis sob
`/api/v1/projects`, `/api/v1/cells` e `/api/v1/robots`, no contrato de service do
template (`ApiResponseHandler` + `Api::Entities::*`), com policy declarada por endpoint
(D3). Toda escrita SHALL registrar `updated_by_person_id` e `updated_at`.

#### Scenario: renomear grava autor e horário nos três níveis

- **WHEN** a pessoa `P1` envia `PATCH /api/v1/cells/<id>` com `{"name": "Célula B", "lock_version": 0}`
- **THEN** a resposta é `200` com `"name": "Célula B"` e `"lock_version": 1`
- **AND** `cells.updated_by_person_id = P1` e `cells.updated_at` foi atualizado

#### Scenario: renomeação concorrente devolve 409

- **WHEN** dois clientes carregam a célula com `lock_version: 3` e ambos enviam `PATCH`
  com `lock_version: 3`, um com `"Solda 01"` e outro com `"Solda 02"`
- **THEN** o primeiro responde `200` com `lock_version: 4` e o segundo responde `409`
- **AND** o corpo do `409` traz o recurso atual (`"Solda 01"`, `lock_version: 4`)
- **AND** o nome final é `Solda 01`, nunca uma mistura ou a última escrita cega

#### Scenario: nome duplicado no mesmo escopo é rejeitado por índice único

- **WHEN** o projeto `P` já tem a célula `Solda 01` e dois `POST` simultâneos tentam criar
  `solda 01` no mesmo projeto
- **THEN** ambos falham com `422` (ou um `201` e um `422`, nunca dois `201`)
- **AND** a rejeição vem do índice único `(project_id, lower(name))`, não de
  `validates uniqueness`

#### Scenario: mesmo nome em projetos diferentes é permitido

- **WHEN** existe a célula `Solda 01` no projeto `P1` e o cliente cria `Solda 01` no projeto `P2`
- **THEN** o servidor responde `201` e as duas células coexistem

### Requirement: exclusão em cascata com fronteira explícita

Excluir um projeto SHALL excluir fisicamente suas células, os robôs dessas células, as
tarefas desses robôs e os avanços e atribuições dessas tarefas, via
`ON DELETE CASCADE` no banco. A exclusão SHALL NOT remover `audit_logs` (D12) nem
`notifications`, e SHALL NOT remover `people`. A entrada de auditoria (§2.8) SHALL ser
gravada na mesma transação da exclusão.

#### Scenario: cascade desce até os avanços

- **WHEN** um projeto com 2 células, 5 robôs, 155 tarefas e 40 avanços é excluído
- **THEN** as 2 células, 5 robôs, 155 tarefas, 40 avanços e as atribuições correspondentes
  deixam de existir
- **AND** a contagem de `audit_logs` do workspace aumenta em 1, não diminui

#### Scenario: notificação apontando para robô excluído não quebra

- **WHEN** existe notificação com `ctx = {pid, cid, rid, tid}` e o robô `rid` é excluído
- **THEN** a exclusão do robô é bem-sucedida (não há FK de `notifications` para `robots`)
- **AND** a notificação continua existindo e legível na lista

#### Scenario: remover pessoa não apaga projeto

- **WHEN** a pessoa `P1` é a `updated_by_person_id` de 3 projetos e é removida do workspace
- **THEN** os 3 projetos continuam existindo com `updated_by_person_id = NULL`
  (`ON DELETE SET NULL`)

#### Scenario: falha na auditoria aborta a exclusão

- **WHEN** a gravação da entrada de auditoria falha durante o `DELETE` de uma célula
- **THEN** a transação é revertida e a célula continua existindo
- **AND** a API responde `500`, não `204`

#### Scenario: membro `view` não pode excluir

- **WHEN** um membro com papel `view` envia `DELETE /api/v1/cells/<id>`
- **THEN** o servidor responde `403` (§4.1 — só `owner` e `edit` excluem)
- **AND** a célula continua existindo

### Requirement: escrita restrita a `owner` e `edit`

Criar, renomear e excluir projeto, célula ou robô SHALL exigir papel `owner` ou `edit`
no workspace corrente (§4.1). A policy SHALL ser declarada explicitamente em cada
endpoint, de modo que o route-sweep de `authorization-policies` falhe se algum endpoint
desta capacidade não declarar a sua.

#### Scenario: membro `view` não cria projeto

- **WHEN** um membro `view` envia `POST /api/v1/projects` com `{"name": "Linha 8"}`
- **THEN** o servidor responde `403` com mensagem pt-BR
- **AND** `SELECT count(*) FROM projects WHERE name = 'Linha 8'` devolve `0`

#### Scenario: membro `view` lê normalmente

- **WHEN** um membro `view` faz `GET /api/v1/projects`
- **THEN** o servidor responde `200` com a lista completa do workspace (§4.1 — ler tudo é permitido a `view`)

#### Scenario: route-sweep cobre todos os endpoints desta capacidade

- **WHEN** o route-sweep spec enumera as rotas montadas sob `projects`, `cells` e `robots`
- **THEN** cada rota tem uma policy declarada
- **AND** o spec falha se um endpoint novo for montado sem declaração

### Requirement: leitura tolerante — coleção ausente é lista vazia

Toda leitura SHALL representar filhos ausentes como coleção vazia e nunca como `null`
nem como erro (§1.4, normalização defensiva). Projeto sem células, célula sem robôs e
robô sem tarefas SHALL responder `200`.

#### Scenario: projeto sem células

- **WHEN** o cliente faz `GET /api/v1/projects/<id>` de um projeto recém-criado
- **THEN** a resposta é `200` com `"cells": []` e `"cells_count": 0`
- **AND** o valor não é `null` nem a chave é omitida

#### Scenario: célula sem robôs e robô sem tarefas

- **WHEN** o cliente faz `GET /api/v1/cells/<id>` de uma célula vazia e
  `GET /api/v1/robots/<id>` de um robô sem tarefas
- **THEN** as respostas são `200` com `"robots": []` e `"tasks": []`, `"tasks_count": 0`

#### Scenario: `progress_cache` vazio vira zeros, não `null`

- **WHEN** um robô é criado e lido antes de qualquer cálculo de progresso
  (`progress_cache = '{}'`)
- **THEN** a entidade responde `"progress": {"weighted": 0, "done": 0, "total": 0}`
- **AND** a tela não precisa distinguir "cache vazio" de "progresso zero"

#### Scenario: listagem vazia é 200, não 404

- **WHEN** um workspace sem nenhum projeto faz `GET /api/v1/projects`
- **THEN** a resposta é `200` com corpo `[]`
