# workspace-core

## ADDED Requirements

### Requirement: Entidade Workspace

O sistema SHALL persistir workspaces numa tabela `workspaces` com `id uuid` PK
gerável pelo cliente (D1), `name text NOT NULL`, `owner_user_id uuid NOT NULL`
referenciando `users`, e `created_at`/`updated_at`. O sistema SHALL garantir no
banco, por índice único em `owner_user_id`, que um usuário é dono de no máximo um
workspace (`§1.1`). O sistema SHALL NOT persistir uma coluna `responsibles` — a
lista de responsáveis é a projeção da tabela `people` do workspace (D11).

#### Scenario: Segundo workspace para o mesmo dono é rejeitado pelo banco
- **WHEN** já existe `workspaces(owner_user_id = U1)` e um `INSERT` tenta criar
  outra linha com `owner_user_id = U1`
- **THEN** o Postgres SHALL levantar violação do índice único
  `index_workspaces_on_owner_user_id`, e o número de linhas com
  `owner_user_id = U1` SHALL permanecer 1

#### Scenario: Id fornecido pelo cliente é aceito
- **WHEN** uma criação de workspace informa `id = "3f2a…-uuid-do-cliente"`
- **THEN** o registro persistido SHALL ter exatamente esse `id`, sem substituição
  por `gen_random_uuid()`

#### Scenario: Coluna responsibles não existe
- **WHEN** a suíte inspeciona `information_schema.columns` para a tabela
  `workspaces`
- **THEN** SHALL NOT haver coluna chamada `responsibles`

### Requirement: Bootstrap do workspace no primeiro login

O sistema SHALL criar, no primeiro login bem-sucedido de um usuário sem workspace
próprio, um workspace com `name = "Workspace de <nome de exibição do dono>"`
(`§1.1`) e, na **mesma transação**, uma `Person` para o dono com `user_id`
preenchido (D10). A operação SHALL ser idempotente.

#### Scenario: Primeiro login cria workspace e Person do dono
- **WHEN** o usuário `maria@exemplo.com`, com nome de exibição `"Maria Silva"`,
  autentica pela primeira vez
- **THEN** SHALL existir exatamente um workspace com
  `name = "Workspace de Maria Silva"` e `owner_user_id` igual ao id dela,
  **E** SHALL existir exatamente uma `Person` nesse workspace com
  `name = "Maria Silva"`, `email = "maria@exemplo.com"` e `user_id` igual ao id
  dela

#### Scenario: Login subsequente não duplica nada
- **WHEN** a mesma Maria autentica uma segunda e uma terceira vez
- **THEN** a contagem de `workspaces` com `owner_user_id` dela SHALL permanecer 1
  e a contagem de `people` nesse workspace SHALL permanecer 1

#### Scenario: Dois logins simultâneos não criam dois workspaces
- **WHEN** duas threads chamam `Workspaces::BootstrapService.call(user: U1)` em
  paralelo, para um `U1` sem workspace
- **THEN** exatamente um workspace SHALL ser criado, **E** nenhuma das duas
  chamadas SHALL levantar `ActiveRecord::RecordNotUnique` — a perdedora releitura
  e devolve o workspace criado pela vencedora

#### Scenario: Dono sem nome de exibição não gera nome truncado
- **WHEN** um usuário autentica via Google com `display_name` vazio e e-mail
  `joao.pereira@fabrica.com.br`
- **THEN** o `name` do workspace SHALL ser `"Workspace de joao.pereira"`
  **E** SHALL NOT ser `"Workspace de "`

#### Scenario: Bootstrap não semeia o catálogo de tarefas-base
- **WHEN** o bootstrap termina
- **THEN** a contagem de `task_templates` do workspace SHALL ser 0 e o sistema
  SHALL ter emitido o evento `workspace.bootstrapped` — a semeadura dos 31 itens
  (`§1.3`) é responsabilidade de `task-catalog`

### Requirement: Imutabilidade do dono do workspace

O sistema SHALL impedir, no banco, qualquer alteração de `workspaces.owner_user_id`
após a criação (`§4.1 inv. 5`), por `REVOKE UPDATE (owner_user_id)` sobre o papel
da aplicação e por trigger `BEFORE UPDATE` que levanta exceção quando o valor
muda.

#### Scenario: API rejeita troca de dono
- **WHEN** o dono do workspace envia `PATCH /api/v1/workspaces/<id>` com
  `{"owner_user_id": "<id de outro usuário>"}`
- **THEN** a resposta SHALL ser `422` e o `owner_user_id` persistido SHALL
  permanecer inalterado

#### Scenario: SQL direto pelo papel da aplicação é negado por privilégio
- **WHEN** uma conexão como `robotrack_app` executa
  `UPDATE workspaces SET owner_user_id = '<outro>' WHERE id = '<ws>'`
- **THEN** o Postgres SHALL levantar `permission denied for column owner_user_id`

#### Scenario: SQL direto por papel privilegiado é negado pelo trigger
- **WHEN** uma conexão como `robotrack_migrator` executa o mesmo `UPDATE`
- **THEN** o trigger `workspaces_owner_immutable` SHALL levantar exceção com
  mensagem que nomeia `§4.1 inv. 5`, e a linha SHALL permanecer inalterada

#### Scenario: Atualizar outras colunas continua funcionando
- **WHEN** o dono envia `PATCH` alterando apenas `name` para
  `"Comissionamento Planta 2"`
- **THEN** a resposta SHALL ser `200` e o `name` persistido SHALL ser o novo valor

### Requirement: Seleção do workspace corrente por request

O sistema SHALL exigir, em toda rota de domínio, o cabeçalho `X-Workspace-Id`, e
SHALL resolver server-side o papel do usuário autenticado naquele workspace antes
de abrir o contexto de tenant. Rotas isentas SHALL constar de uma allowlist
explícita (autenticação, health, `GET /api/v1/workspaces`).

#### Scenario: Header ausente em rota de domínio
- **WHEN** um usuário autenticado chama `GET /api/v1/projects` sem
  `X-Workspace-Id`
- **THEN** a resposta SHALL ser `400` com código de erro
  `workspace_context_missing`, **E** nenhuma query de domínio SHALL ser executada

#### Scenario: Usuário de outro workspace é negado
- **WHEN** o usuário `bruno@outra-empresa.com`, sem membership nem propriedade no
  workspace `WS-A`, chama `GET /api/v1/projects` com `X-Workspace-Id: WS-A`
- **THEN** a resposta SHALL ser `403` com código `workspace_access_denied`,
  **E** a variável de sessão `app.current_workspace_id` SHALL NOT ter sido setada
  para `WS-A`

#### Scenario: Workspace inexistente não revela existência
- **WHEN** um usuário autenticado envia `X-Workspace-Id` com um uuid válido que
  não corresponde a nenhum workspace
- **THEN** a resposta SHALL ser `403` (o mesmo código do cenário anterior) e
  SHALL NOT ser `404` — a diferença de status vazaria a existência do tenant

#### Scenario: Membro válido abre o contexto
- **WHEN** um membro `edit` do workspace `WS-A` chama uma rota de domínio com
  `X-Workspace-Id: WS-A`
- **THEN** `current_setting('app.current_workspace_id')` dentro da request SHALL
  ser `WS-A`, **E** `current_role` SHALL ser `:edit`

### Requirement: Índice de workspaces do usuário como cache de UI

O sistema SHALL expor `GET /api/v1/workspaces` devolvendo os workspaces em que o
usuário autenticado é dono ou membro, cada um com `id`, `name` e `role`, derivado
ao vivo de `workspaces` e `memberships`. O sistema SHALL NOT persistir uma tabela
de índice por usuário, e SHALL NOT aceitar papel vindo do cliente em nenhuma
rota (`§1.1 Índice do usuário`, `§4.1 inv. 2`).

#### Scenario: Listagem reflete propriedade e membership
- **WHEN** o usuário é dono de `WS-A` e membro `view` de `WS-B`, e não tem
  relação com `WS-C`
- **THEN** a resposta SHALL conter exatamente dois itens —
  `{id: WS-A, role: "owner"}` e `{id: WS-B, role: "view"}` — e SHALL NOT
  mencionar `WS-C`

#### Scenario: Adulteração do índice de UI não concede acesso
- **WHEN** o cliente injeta `{"id": "WS-C", "name": "…", "role": "owner"}` no
  `localStorage` e emite `GET /api/v1/projects` com `X-Workspace-Id: WS-C`
- **THEN** a resposta SHALL ser `403`, **E** o papel efetivo SHALL ser resolvido
  a partir de `workspaces.owner_user_id`/`memberships` e nunca do payload do
  cliente

#### Scenario: Papel enviado pelo cliente é ignorado
- **WHEN** uma request de domínio inclui um cabeçalho ou parâmetro
  `role=owner` além do `X-Workspace-Id` de um workspace onde o usuário é `view`
- **THEN** o papel usado pelo servidor SHALL ser `view`, e qualquer ação
  restrita a `owner` SHALL ser negada

#### Scenario: Mudança de papel aparece sem invalidação manual
- **WHEN** o dono de `WS-B` altera o papel do usuário de `view` para `edit` e o
  usuário chama `GET /api/v1/workspaces` em seguida
- **THEN** o item de `WS-B` SHALL trazer `role: "edit"` sem que nenhuma rotina de
  invalidação de índice tenha sido executada

#### Scenario: Não existe tabela de índice materializada
- **WHEN** a suíte inspeciona as tabelas do banco
- **THEN** SHALL NOT existir tabela `user_workspace_index` nem equivalente com
  lista de workspaces por usuário
