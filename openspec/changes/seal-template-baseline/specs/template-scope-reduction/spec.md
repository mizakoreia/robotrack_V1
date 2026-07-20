# template-scope-reduction

## ADDED Requirements

### Requirement: Backup verificado antes de descarte de dados

O sistema SHALL exigir um dump binário do banco, com restauração comprovada em
um banco descartável, antes da execução de qualquer migration que remova tabela
ou coluna.

#### Scenario: Dump é restaurável, não apenas gerado

- **WHEN** o dump `backend/tmp/backups/pre-seal-<AAAAMMDD-HHMM>.dump` é gerado e
  restaurado com `pg_restore` em um banco `robotrack_restore_check`
- **THEN** a restauração SHALL terminar com código de saída `0` e
  `SELECT count(*) FROM pg_tables WHERE schemaname='public'` no banco restaurado
  SHALL retornar o mesmo valor do banco de origem

#### Scenario: Migration destrutiva declara o caminho de reversão

- **WHEN** `rails db:rollback` é executado sobre a migration `RemoveTemplateTables`
- **THEN** ela SHALL levantar `ActiveRecord::IrreversibleMigration` com uma
  mensagem que nomeia o diretório `tmp/backups/` como caminho de recuperação, em
  vez de recriar tabelas vazias

### Requirement: Remoção do módulo de cobrança e Asaas

O sistema SHALL remover todo o código, entities, endpoints e tabelas de
cobrança, assinaturas, pedidos e catálogo de produtos, incluindo os arquivos
órfãos de webhook Asaas na raiz do repositório.

#### Scenario: Endpoint de sessão de checkout deixa de existir

- **WHEN** `POST /auth/v1/checkout/session` é emitida com um `payment_id` qualquer
- **THEN** a resposta SHALL ser `404`, e a rota NÃO SHALL aparecer em
  `Api::Root.routes`

#### Scenario: Nenhuma constante de cobrança é referenciada

- **WHEN** `Rails.application.eager_load!` é executado após a remoção
- **THEN** ele SHALL terminar sem erro, e uma varredura de `backend/app/` por
  `Purchase`, `Subscription`, `Plan`, `Order`, `PlanFeature` ou `Asaas` SHALL
  retornar `0` ocorrências

#### Scenario: Arquivos órfãos da raiz não existem

- **WHEN** a raiz do repositório é listada
- **THEN** `asaas_payment_webhook_service.rb`, `asaas_webhook_service.rb` e
  `webhooks.rb` NÃO SHALL estar presentes

### Requirement: Remoção do RBAC por planos de cobrança

O sistema SHALL remover o mecanismo de permissões atrelado a planos —
endpoints, serviço de sincronização, canal de tempo real, entities e as quatro
tabelas correspondentes — sem remover `UserType` nem os predicados
`User#og?` / `User#client?`.

#### Scenario: Endpoint de permissões deixa de existir

- **WHEN** `GET /api/v1/permissions` é emitida com um JWT válido de um usuário OG
- **THEN** a resposta SHALL ser `404`

#### Scenario: Gate de autorização remanescente continua funcionando

- **WHEN** um usuário com `user_type.name = 'client'` emite `GET /api/v1/users`
- **THEN** a resposta SHALL ser `403`, provando que `User#og?` sobreviveu à
  remoção e continua sendo aplicado

### Requirement: Remoção de Leads, Operations e mensagens de lead

O sistema SHALL remover os endpoints, serviços, models, entities, canal e
tabelas de `Lead`, `LeadMessage` e `Operation`.

#### Scenario: Endpoints de lead deixam de existir

- **WHEN** `GET /api/v1/leads`, `GET /api/v1/lead_messages` e
  `GET /api/v1/operations` são emitidos com JWT válido
- **THEN** cada um SHALL responder `404`

#### Scenario: Remoção respeita a dependência Lead → Operation

- **WHEN** a migration `RemoveTemplateTables` é executada
- **THEN** `lead_messages` SHALL ser descartada antes de `leads`, e `leads`
  antes de `operations`, de modo que nenhuma violação de chave estrangeira
  ocorra e `force: :cascade` não seja o mecanismo que faz a remoção funcionar

### Requirement: Remoção do módulo WhatsApp e Evolution

O sistema SHALL remover o namespace `/whats/v1/*`, os quatro models `Polemk*`,
`EvolutionConnection`, `WhatsAppWebhookService`, `WhatsMessageService`, o canal
`WhatsappInstanceChannel` e as quatro tabelas correspondentes.

#### Scenario: Webhook de mensagens do WhatsApp deixa de existir

- **WHEN** `POST /whats/v1/webhooks/messages-upsert` é emitida sem autenticação,
  como a Evolution fazia
- **THEN** a resposta SHALL ser `404`, e não `200` nem `401`

#### Scenario: Remoção de WhatsApp ocorre após a remoção de Lead

- **WHEN** o histórico de commits desta mudança é inspecionado
- **THEN** o commit que remove `WhatsAppWebhookService` SHALL vir depois do que
  remove o model `Lead`, e cada commit intermediário SHALL passar
  `Rails.application.eager_load!` sem `NameError`

### Requirement: Remoção do magic-login de seis dígitos

O sistema SHALL remover o fluxo de autenticação por código de seis dígitos —
endpoints, cinco serviços de `Auth::`, `AuthMailer` e views, helpers de
rate-limit, models `LoginCode` e `LoginAttempt` e suas tabelas — mantendo o
fluxo OAuth intacto, conforme **D4**.

#### Scenario: Solicitação de código deixa de existir

- **WHEN** `POST /auth/v1/magic_login/request_code` é emitida com
  `{"identifier":"a@b.com","method":"email"}`
- **THEN** a resposta SHALL ser `404`, e nenhuma linha SHALL ser inserida em
  nenhuma tabela

#### Scenario: OAuth continua operante após a remoção

- **WHEN** `GET /auth/v1/oauth/google_url` é emitida sem autenticação
- **THEN** a resposta SHALL ser `200` com uma chave `url` apontando para
  `accounts.google.com`

#### Scenario: Model User não referencia mais os códigos

- **WHEN** `User.reflect_on_all_associations.map(&:name)` é inspecionado
- **THEN** ele NÃO SHALL conter `:login_codes` nem `:login_attempts`, e
  `User.create!` com atributos válidos SHALL persistir sem erro

#### Scenario: Helpers de rate-limit do magic-login somem sem quebrar o base

- **WHEN** `Api::Auth::V1::Base` é carregada
- **THEN** ela NÃO SHALL definir `check_rate_limit!`, `check_brute_force!` nem
  `rate_limit_key`, e nenhum endpoint remanescente SHALL chamá-los

### Requirement: Superfície de API resultante é a mínima do RoboTrack

O sistema SHALL expor, após a redução, apenas as rotas necessárias à Onda 1.

#### Scenario: Inventário de rotas montadas

- **WHEN** `Api::Root.routes.map { |r| "#{r.request_method} #{r.path}" }` é
  inspecionado
- **THEN** o conjunto SHALL estar contido em `/swagger_doc`, `/auth/v1/oauth/*`,
  `/auth/v1/sessions/*`, `/auth/v1/me`, `/api/v1/users*`, `/api/v1/uploads*`,
  `/api/v1/countries`, `/api/v1/downloads*`

#### Scenario: Swagger gera sem exceção após a remoção

- **WHEN** `GET /swagger_doc` é emitida
- **THEN** a resposta SHALL ser `200` com JSON válido, e o campo `info.title`
  SHALL ser `RoboTrack`

### Requirement: Seeds e esquema reproduzíveis do zero

O sistema SHALL permitir recriar o ambiente completo a partir de um banco vazio,
eliminando o drift entre `db/schema.rb` e `db/migrate/`.

#### Scenario: Recriação a partir de banco vazio

- **WHEN** `rails db:drop db:create db:schema:load db:seed` é executado
- **THEN** SHALL terminar com código `0`, e `UserType.count` SHALL ser `2`
  (`OG` e `client`)

#### Scenario: Seeds não semeiam módulos removidos

- **WHEN** `db/seeds.rb` é inspecionado
- **THEN** ele NÃO SHALL referenciar `SEED_WHATS_INSTANCE`, `SEED_LEADS`,
  `SEED_LEAD_MESSAGES`, `SEED_CLIENT_APPS` nem nenhuma constante removida

### Requirement: Rebranding de POLEMK para RoboTrack

O sistema SHALL remover toda ocorrência do branding herdado `POLEMK`, `Polemk` e
`polemk` de código, configuração e seeds.

#### Scenario: Nenhuma ocorrência de branding herdado

- **WHEN** `backend/app/`, `backend/config/`, `backend/db/` e `frontend/src/`
  são varridos, sem diferenciar maiúsculas, pela sequência `polemk`
- **THEN** o número de ocorrências SHALL ser `0`

#### Scenario: Swagger UI exibe o nome correto

- **WHEN** `config/initializers/grape_swagger_rails.rb` é carregado
- **THEN** `GrapeSwaggerRails.options.app_name` SHALL ser `RoboTrack API`, e não
  `Polemk API`
