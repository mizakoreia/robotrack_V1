# tenant-isolation

## ADDED Requirements

### Requirement: workspace_id NOT NULL desnormalizado em toda tabela de domínio

O sistema SHALL exigir que toda tabela de domínio carregue
`workspace_id uuid NOT NULL REFERENCES workspaces(id)`, ainda que o valor seja
derivável por join, e SHALL indexar essa coluna (D2). Tabelas não-tenant SHALL
constar de uma allowlist explícita: `users`, `workspaces`, `jwt_denylist`,
`schema_migrations`, `ar_internal_metadata`.

#### Scenario: Tabela de domínio sem a coluna reprova o CI
- **WHEN** uma migration cria `tasks` sem `workspace_id`
- **THEN** a spec de guarda de tenancy SHALL falhar nomeando `tasks`, **E** a
  mensagem SHALL indicar a allowlist como o único caminho de exceção

#### Scenario: workspace_id nullable reprova o CI
- **WHEN** `cells.workspace_id` existe mas permite `NULL`
- **THEN** a spec de guarda SHALL falhar — uma linha com `workspace_id NULL`
  nunca satisfaz a política e vira dado órfão invisível

#### Scenario: Coluna presente mesmo quando redundante
- **WHEN** `task_advances` é criada, tendo `task_id` que já determina o workspace
  por três joins
- **THEN** a tabela SHALL ainda assim ter `workspace_id NOT NULL` — a política
  RLS é avaliada por linha e não pode depender de join recursivo

#### Scenario: Índice em workspace_id existe
- **WHEN** a suíte inspeciona os índices de cada tabela de domínio
- **THEN** cada uma SHALL ter índice cujo primeiro atributo é `workspace_id`

### Requirement: Row Level Security habilitada e forçada

O sistema SHALL habilitar `ROW LEVEL SECURITY` e `FORCE ROW LEVEL SECURITY` em
toda tabela de tenant, com a política `tenant_isolation` cujo `USING` e
`WITH CHECK` comparam `workspace_id` com
`current_setting('app.current_workspace_id', true)::uuid`.

#### Scenario: FORCE está ativo, não apenas ENABLE
- **WHEN** a suíte consulta `pg_class.relrowsecurity` e `pg_class.relforcerowsecurity`
  para cada tabela de tenant
- **THEN** ambos SHALL ser `true` — só `ENABLE` deixaria o dono das tabelas, que é
  quem roda as migrations, ignorar a política

#### Scenario: Política existe com USING e WITH CHECK
- **WHEN** a suíte consulta `pg_policies` para cada tabela de tenant
- **THEN** SHALL haver política `tenant_isolation` com `qual` e `with_check`
  ambos não nulos — `WITH CHECK` ausente permitiria `INSERT` de linha com
  `workspace_id` alheio

#### Scenario: Políticas de controle usam também o usuário corrente
- **WHEN** a suíte inspeciona as políticas de `workspaces` e `memberships`
- **THEN** elas SHALL referenciar `app.current_user_id`, de modo que a listagem
  de workspaces do usuário funcione antes de haver tenant escolhido

### Requirement: Contexto de tenant setado por request

O sistema SHALL abrir o contexto de tenant via `Tenant.with(workspace_id:,
user_id:)`, que emite `set_config(..., true)` dentro de uma transação
(`SET LOCAL`), em três pontos e só três: o bloco `before` de
`backend/app/controllers/api/root.rb`, o middleware de servidor do Sidekiq e a
conexão do ActionCable.

#### Scenario: Variável é local à transação
- **WHEN** uma request de domínio termina e a conexão volta ao pool, e em seguida
  outra request usa a mesma conexão sem abrir contexto
- **THEN** `current_setting('app.current_workspace_id', true)` SHALL ser `NULL`
  na segunda request — o valor SHALL NOT sobreviver ao fim da transação

#### Scenario: Exceção no meio da request não deixa contexto sujo
- **WHEN** uma request de domínio levanta exceção após abrir o contexto
- **THEN** o `ROLLBACK` SHALL descartar a variável, **E** a request seguinte na
  mesma conexão SHALL ver `NULL`

#### Scenario: Job de domínio recebe workspace_id explícito
- **WHEN** um job de domínio é enfileirado sem `workspace_id` como primeiro
  argumento
- **THEN** o middleware do Sidekiq SHALL levantar erro antes de executar o
  `perform`, **E** o job SHALL ir para a fila de mortos em vez de rodar sem
  isolamento

#### Scenario: Rota sem tenant não abre transação
- **WHEN** `POST /api/v1/auth/sign_in` ou `GET /api/v1/workspaces` é chamada
- **THEN** nenhuma transação de tenant SHALL ser aberta, **E** a rota SHALL
  constar da allowlist explícita de rotas sem tenant

#### Scenario: Rota de domínio fora da allowlist e sem contexto reprova o CI
- **WHEN** um endpoint novo de domínio é montado sem passar pela resolução de
  tenant nem entrar na allowlist
- **THEN** a spec de varredura de rotas SHALL falhar nomeando o verbo e o caminho
  (mesmo mecanismo do route-sweep de `authorization-policies`, D3)

### Requirement: Fail-closed na ausência de contexto

O sistema SHALL garantir que, sem `app.current_workspace_id` setada, leituras de
tabelas de tenant retornem zero linhas e escritas sejam rejeitadas pelo banco.

#### Scenario: Leitura sem contexto retorna vazio
- **WHEN** um `rails console` conectado como `robotrack_app`, sem abrir
  `Tenant.with`, executa `Person.count` num banco com 40 pessoas
- **THEN** o resultado SHALL ser `0`

#### Scenario: Escrita sem contexto é rejeitada
- **WHEN** a mesma sessão executa `Person.create!(workspace_id: "WS-A", name: "X")`
- **THEN** o Postgres SHALL levantar `new row violates row-level security policy
  for table "people"`

#### Scenario: Request de domínio sem variável de sessão não vaza
- **WHEN** um defeito faz uma rota de domínio pular a resolução de tenant e
  consultar `projects` diretamente
- **THEN** a resposta SHALL ser uma lista vazia e SHALL NOT conter projetos de
  nenhum workspace — a falha SHALL ser visível como ausência de dado, nunca como
  vazamento

#### Scenario: X-Skip-Auth não fornece contexto
- **WHEN** uma request de domínio envia `X-Skip-Auth: 1` sem token
- **THEN** a resposta SHALL ser `401` (dependência de `seal-template-baseline`),
  **E** nenhum contexto de tenant SHALL ser aberto

### Requirement: Isolamento entre tenants em leitura e escrita

O sistema SHALL impedir que uma sessão com contexto de `WS-A` leia ou escreva
linhas de `WS-B`, independentemente do que o código Ruby peça.

#### Scenario: find por id de outro tenant não encontra
- **WHEN** dentro de `Tenant.with(workspace_id: "WS-A")` o código executa
  `Project.find("<id de projeto de WS-B>")`
- **THEN** SHALL ser levantado `ActiveRecord::RecordNotFound` e SHALL NOT ser
  devolvido o projeto de `WS-B`

#### Scenario: unscoped não contorna a política
- **WHEN** dentro do contexto de `WS-A` o código executa
  `Project.unscoped.count` num banco com 12 projetos em `WS-A` e 30 em `WS-B`
- **THEN** o resultado SHALL ser `12`

#### Scenario: SQL cru não contorna a política
- **WHEN** dentro do contexto de `WS-A` o código executa
  `ActiveRecord::Base.connection.select_all("SELECT * FROM projects")`
- **THEN** SHALL retornar apenas as 12 linhas de `WS-A`

#### Scenario: Escrita marcada com tenant alheio é rejeitada
- **WHEN** dentro do contexto de `WS-A` o código executa
  `Person.create!(workspace_id: "WS-B", name: "Intruso")`
- **THEN** o `WITH CHECK` da política SHALL rejeitar o `INSERT`

#### Scenario: UPDATE não consegue mover linha entre tenants
- **WHEN** dentro do contexto de `WS-A` o código executa
  `UPDATE projects SET workspace_id = 'WS-B' WHERE id = '<projeto de WS-A>'`
- **THEN** o `WITH CHECK` SHALL rejeitar a operação e a linha SHALL permanecer em
  `WS-A`

#### Scenario: DELETE não alcança outro tenant
- **WHEN** dentro do contexto de `WS-A` o código executa
  `Project.delete_all` num banco com 30 projetos em `WS-B`
- **THEN** os 30 projetos de `WS-B` SHALL permanecer intactos

### Requirement: Papel de banco da aplicação sem privilégio de contorno

O sistema SHALL rodar a aplicação com o papel `robotrack_app`, sem `SUPERUSER` e
sem `BYPASSRLS`, distinto do papel `robotrack_migrator` que executa DDL. As duas
credenciais SHALL vir de `DATABASE_URL` e `MIGRATION_DATABASE_URL`
(provisionamento em `delivery-and-observability`).

#### Scenario: Papel privilegiado em runtime reprova o CI
- **WHEN** a spec de guarda consulta `pg_roles` para o papel da conexão corrente
  e encontra `rolsuper = true` ou `rolbypassrls = true`
- **THEN** a suíte SHALL falhar com mensagem explicando que a RLS está desligada
  de fato — este é o modo de falha padrão de ambientes de desenvolvimento

#### Scenario: Papel da aplicação não altera o dono do workspace
- **WHEN** `robotrack_app` tenta `UPDATE workspaces SET owner_user_id = …`
- **THEN** o Postgres SHALL negar por privilégio de coluna (`§4.1 inv. 5`)

#### Scenario: Migrations continuam funcionando pelo papel de DDL
- **WHEN** `rails db:migrate` roda com `MIGRATION_DATABASE_URL`
- **THEN** as migrations SHALL concluir, **E** as tabelas criadas SHALL pertencer
  a `robotrack_migrator` com `FORCE ROW LEVEL SECURITY` ativo

### Requirement: Integridade referencial que não cruza tenants

O sistema SHALL usar chave estrangeira composta incluindo `workspace_id` em toda
referência entre tabelas de domínio, apoiada em índice único
`(workspace_id, id)` na tabela referenciada.

#### Scenario: FK composta rejeita referência cross-tenant
- **WHEN** um `INSERT` numa tabela de domínio de `WS-A` referencia um pai que
  existe apenas em `WS-B`
- **THEN** o Postgres SHALL levantar violação de chave estrangeira, **E** SHALL
  NOT criar uma linha que a RLS tornaria invisível e indepurável

#### Scenario: Toda FK de domínio inclui workspace_id
- **WHEN** a spec de guarda enumera as chaves estrangeiras entre tabelas de
  tenant
- **THEN** cada uma SHALL incluir `workspace_id` entre as colunas, ou constar de
  uma allowlist justificada no `design.md`

### Requirement: Esquema versionado em SQL

O sistema SHALL usar `config.active_record.schema_format = :sql` e versionar
`db/structure.sql`, porque políticas RLS, triggers, `REVOKE` de coluna,
constraints com expressão e enums nativos não são representáveis em
`db/schema.rb`.

#### Scenario: schema.rb não é regenerado
- **WHEN** `rails db:migrate` roda
- **THEN** `db/schema.rb` SHALL NOT existir, **E** `db/structure.sql` SHALL
  conter as linhas `FORCE ROW LEVEL SECURITY` e `CREATE POLICY tenant_isolation`

#### Scenario: Banco reconstruído do zero nasce isolado
- **WHEN** `db:drop && db:create && db:schema:load` é executado num ambiente
  limpo e em seguida a suíte de isolamento roda
- **THEN** todos os cenários de negação desta capability SHALL passar — um banco
  carregado do esquema SHALL NOT nascer sem RLS
