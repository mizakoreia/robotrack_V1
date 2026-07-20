# tasks — seal-template-baseline

Ordem obrigatória: grupos 1 → 8. Os grupos 3 a 6 removem consumidores antes de
produtores (design.md, D-E); inverter a ordem deixa o boot quebrado sem bisseção
possível. O grupo 7 é o único destrutivo em dados e começa por backup.

## 1. Vedação de autenticação HTTP

- [x] 1.1 Em `backend/app/controllers/api/root.rb`, remover o bloco `skip_header`
  e o fallback `ClientApplication.active.find_by(token:)` (com o helper
  `current_client` e as escritas em `env['api.current_client']`), extraindo a
  allowlist para `Api::Root::PUBLIC_ROUTES` congelada, reduzida a `/swagger_doc`,
  `/api/v1/countries` e `/auth/v1/oauth/(google_url|callback)`
  (template-security-hardening §Eliminação do bypass e §Remoção do fallback —
  `GET /api/v1/users` com `X-Skip-Auth: 1` e sem `Authorization` passa a retornar
  401 em vez de 200, e um token que existia em `client_applications` passa a
  retornar 401 em vez de autenticar sem usuário).
- [x] 1.2 Escrever spec de request que enumera `Api::Root.routes`, subtrai
  `PUBLIC_ROUTES` e exige 401 em cada rota restante, emitida duas vezes: com e
  sem `X-Skip-Auth: 1` (§Allowlist — o spec falha nomeando método e caminho da
  primeira rota que responder algo diferente de 401; é o ancestral do route-sweep
  da D3 e `authorization-policies` o estende em vez de reinventar).
- [x] 1.3 Verificação: reintroduzir o `skip_header` temporariamente e confirmar
  que 1.2 **falha**; reverter (§Allowlist — um spec que continua verde com o
  bypass de volta não tem poder de detecção e não vale como prova).

## 2. Vedação do ActionCable e caminho de erro

- [x] 2.1 Fazer `find_verified_user` em
  `backend/app/channels/application_cable/connection.rb` chamar
  `reject_unauthorized_connection` quando não resolve `User`, remover
  `allow_public_checkout_subscription?` e `decode_user_id`, e deletar os quatro
  canais legados e o `DashboardKpisBroadcastJob`
  (template-security-hardening §ActionCable — conexão sem `?token=` é rejeitada
  em vez de estabelecida com `current_user = nil`, e `app/channels/` fica só com
  os dois arquivos de `application_cable/`).
- [x] 2.2 Criar `backend/app/services/error_reporter.rb` delegando para
  `Rails.error.report` e substituir a chamada a `ExceptionNotifier` em
  `root.rb:118` (§Notificação de exceção — o `rescue_from` deixa de levantar
  `NameError: uninitialized constant ExceptionNotifier`; o destino real do erro
  fica para `delivery-and-observability` plugar sob o mesmo módulo).
- [x] 2.3 Colapsar os três `rescue_from :all` de `api/root.rb`, `api/v1/base.rb`
  e `api/auth/v1/base.rb` num único em `Api::Root`, que responde
  `{error, message, request_id}` e loga backtrace em separado
  (§Resposta de erro — o corpo da resposta 500 deixa de casar com
  `/BACKTRACE|\.rb:\d+/`, que hoje casa porque `error!(error_backtrace)` serializa
  o backtrace inteiro do servidor ao cliente).
- [x] 2.4 Verificação: spec de `ActionCable::Connection` (`connect "/cable"` sem
  token → `UnauthorizedError`; com token válido → `current_user.id` correto) e
  spec de request que provoca exceção real e asserta ausência de backtrace no
  corpo com presença do `request_id` no log.

## 3. Fase 1 de remoção — Cobrança e Asaas

- [x] 3.1 Deletar `app/services/analytics_service.rb`,
  `app/controllers/api/v1/analytics.rb`, `app/controllers/api/entities/analytics/`,
  `entities/purchase.rb`, `entities/sale.rb` e desmontar `namespace :analytics`
  de `api/v1/base.rb` (template-scope-reduction §Cobrança — `AnalyticsService`
  chama `Purchase.all` e `Subscription.all`, models que não existem em disco;
  `GET /api/v1/analytics` deixa de existir em vez de dar NameError em runtime).
- [x] 3.2 Deletar `app/services/auth/checkout_session_service.rb` e
  `app/controllers/api/auth/v1/checkout.rb`, desmontar de `api/auth/v1/base.rb`,
  remover `checkoutSession` de `frontend/src/lib/api/endpoints.ts` e apagar
  `asaas_payment_webhook_service.rb`, `asaas_webhook_service.rb` e `webhooks.rb`
  da raiz do repo (§Cobrança — `POST /auth/v1/checkout/session` retorna 404 e a
  raiz do repositório não contém mais os três arquivos que nenhum autoload path
  carrega).
- [x] 3.3 Verificação: `bin/rails runner 'Rails.application.eager_load!'` sai com
  código 0 e `grep -rin "purchase\|subscription\|asaas" backend/app` retorna
  vazio.

## 4. Fase 2 de remoção — RBAC por planos

- [x] 4.1 Deletar `permissions_sync_service.rb`, `api/v1/permissions.rb`, as três
  entities `permission*` e os quatro models `permission*`/`user_permission`,
  desmontando `namespace :permissions` de `api/v1/base.rb`, preservando
  `user_type.rb` e `User#og?`/`#client?` (§RBAC — `GET /api/v1/permissions`
  retorna 404, e `PermissionsSyncService`, que referenciava `Purchase` e `Plan`
  já removidos em 3.1, sai antes de virar NameError).
- [x] 4.2 Verificação: `eager_load!` verde e spec de request provando que um
  usuário `client` ainda recebe 403 e um `og` recebe 200 em `GET /api/v1/users`
  (§RBAC — o gate remanescente não pode cair junto; `workspace-tenancy` só o
  substitui na Onda 1).

## 5. Fase 3 de remoção — Leads, Operations, WhatsApp/Evolution

- [x] 5.1 Deletar os endpoints `leads.rb`, `lead_messages.rb`, `operations.rb`,
  suas entities e os quatro services (`lead_service`, `lead_message_service`,
  `lead_cross_channel_service`, `operation_service`), desmontar os três
  namespaces de `api/v1/base.rb`, e remover `LeadsChatPage.tsx` com sua rota e os
  `leadsApi`/`leadMessagesApi` de `endpoints.ts` (§Leads — os três caminhos
  retornam 404; `LeadCrossChannelService` depende de `PolemkInstance` e sai antes
  do módulo Whats para não deixar NameError transitório).
- [x] 5.2 Deletar o namespace `app/controllers/api/whats/` inteiro,
  `evolution_connection.rb`, `whats_app_webhook_service.rb`,
  `whats_message_service.rb`, os quatro `polemk_*_service.rb` e as entities
  `polemk_*`, desmontar `Api::Whats::V1::Base` de `api/root.rb`, e remover
  `WhatsappPage.tsx` com sua rota e os quatro grupos de `endpoints.ts`
  (§WhatsApp — `POST /whats/v1/webhooks/messages-upsert` retorna 404, não 200;
  esse webhook é o que criava `Lead`, por isso vem depois de 5.1).
- [x] 5.3 Deletar os models `lead.rb`, `lead_message.rb`, `operation.rb` e os
  quatro `polemk_*.rb` (§Leads — models saem por último na fase porque
  `Lead belongs_to :operation` e os services removidos acima os referenciavam).
- [x] 5.4 Verificação: `eager_load!` verde e
  `grep -rin "lead\|polemk\|evolution" backend/app frontend/src/lib` vazio.

## 6. Fase 4 de remoção — Magic-login (D4)

- [x] 6.1 Deletar `api/auth/v1/{magic_login,code_validation,registration}.rb`, os
  cinco `Auth::*Service` do fluxo de código, `email_service.rb`, `auth_mailer.rb`
  e `app/views/auth_mailer/`, desmontá-los de `api/auth/v1/base.rb` e remover do
  `PUBLIC_ROUTES` as regex de `magic_login`, `code_validation`, `pre_register`,
  `verify_code` e `complete_registration` (§Magic-login —
  `POST /auth/v1/magic_login/request_code` retorna 404 e nenhuma linha é inserida
  em nenhuma tabela).
- [x] 6.2 Remover de `api/auth/v1/base.rb` os helpers `check_rate_limit!`,
  `check_brute_force!` e `rate_limit_key`, de `user.rb` os `has_many :login_codes`
  e `:login_attempts` com `active_login_code`/`can_request_new_code?`, e deletar
  os models `login_code.rb` e `login_attempt.rb` (§Magic-login —
  `User.reflect_on_all_associations` não contém `:login_codes` e `User.create!`
  com atributos válidos persiste).
- [x] 6.3 Deletar `features/auth/{MagicLogin,CodeValidation,CompleteRegistration,AuthFlow}.tsx`,
  podar `requestMagicCode`/`validateMagicCode`/`canResendCode` de `endpoints.ts` e
  reduzir `LoginPage.tsx` ao botão de OAuth (§Magic-login —
  `GET /auth/v1/oauth/google_url` continua retornando 200 com URL de
  `accounts.google.com`, provando que só o fluxo de código caiu).
- [x] 6.4 Verificação: `eager_load!` verde e spec de request confirmando 404 em
  `/auth/v1/magic_login/request_code` e 200 em `/auth/v1/oauth/google_url`.

## 7. Fase 5 — Descarte de tabelas, seeds e branding

- [ ] 7.1 Gerar `pg_dump -Fc` em `backend/tmp/backups/pre-seal-<AAAAMMDD-HHMM>.dump`
  e **restaurá-lo** em um banco `robotrack_restore_check`
  (§Backup verificado — `pg_restore` sai com código 0 e a contagem de tabelas do
  banco restaurado bate com a da origem; dump gerado e não restaurado não conta
  como backup).
- [ ] 7.2 Escrever e rodar a migration `RemoveTemplateTables`, descartando as 22
  tabelas na ordem filhas→mães (`order_items` antes de `orders`/`items`;
  `plan_feature_*` antes de `plans`; `lead_messages` antes de `leads` antes de
  `operations`), com `down` levantando `ActiveRecord::IrreversibleMigration`
  apontando `tmp/backups/` (§Backup verificado — `rails db:rollback` levanta a
  exceção nomeando o diretório, em vez de recriar tabelas vazias que dariam falsa
  sensação de reversibilidade).
- [ ] 7.3 Reescrever `db/seeds.rb` para conter apenas
  `UserType.seed_default_types!` e um usuário OG de desenvolvimento
  (§Seeds — o arquivo deixa de referenciar `SEED_WHATS_INSTANCE`, `SEED_LEADS`,
  `SEED_LEAD_MESSAGES` e `SEED_CLIENT_APPS`, que hoje semeiam módulos removidos).
- [ ] 7.4 Substituir "POLEMK WHATS", "Polemk API" e `ROBOTRACK_WHATS` por
  RoboTrack em `api/root.rb`, `api/v1/base.rb`, `api/auth/v1/base.rb` e
  `config/initializers/grape_swagger_rails.rb`, e atualizar `.env.example`
  removendo variáveis de Evolution, Asaas e SMTP do magic-login
  (§Rebranding — `grep -rin polemk` em `backend/{app,config,db}` e `frontend/src`
  retorna 0 ocorrências).
- [ ] 7.5 Verificação: `rails db:drop db:create db:schema:load db:seed` num banco
  vazio sai com código 0 e `UserType.count == 2` (§Seeds — prova que o drift de
  10 tabelas presentes em `schema.rb` sem arquivo de migration foi eliminado).

## 8. Infraestrutura de teste e suítes verdes

- [ ] 8.1 Criar `backend/spec/factories/` para `User` e `UserType` com sequência
  de e-mail, e o spec de sanidade que itera `FactoryBot.factories` chamando
  `create` em cada uma (test-harness-baseline §Factories —
  `create_list(:user, 50)` persiste sem violar o índice único de `email`, e a
  falha de uma factory nomeia a factory em vez de estourar num spec de request
  meses depois).
- [ ] 8.2 Criar `backend/spec/support/request_auth_helper.rb` com
  `auth_headers(user, expired: false)` e incluí-lo por
  `config.include ..., type: :request` (§Helper — `grep -rn "def bearer_for"
  backend/spec` retorna 0 e `auth_headers(user, expired: true)` produz 401, para
  que o caminho negativo seja escrevível sem manipular JWT à mão).
- [ ] 8.3 Configurar `database_cleaner-active_record` em `rails_helper.rb` com
  truncation apenas para exemplos marcados, mantendo
  `use_transactional_fixtures = true` (§Estratégia de limpeza — um exemplo
  `js: true` que grava por outra conexão é limpo, e a suíte transacional não
  fica mais lenta por truncar o que não precisa).
- [ ] 8.4 Deletar os oito specs backend de módulos removidos e os oito testes
  órfãos do frontend, podar `lib/api/__tests__/auth.test.ts` das asserções de
  magic-login e reescrever `swagger_spec.rb` para a superfície reduzida
  (§Suíte frontend — `npx vitest run` deixa de emitir `Failed to resolve import`
  para `CheckoutPage` e `PaymentsPage`, e `grep -rn "it.skip\|describe.skip"
  frontend/src` retorna 0; `skip` seria uma suíte verde que mente).
- [ ] 8.5 Escrever teste de `lib/api/client.ts` injetando duas 401 concorrentes
  (§Suíte frontend — ocorre exatamente 1 POST de refresh e 2 retentativas, não 2
  refreshes; o single-flight não tem cobertura hoje e `offline-pwa` depende dele).
- [ ] 8.6 Verificação final: num clone limpo, `bundle install`,
  `rails db:create db:schema:load`, `bundle exec rspec`, `npm ci` e
  `npx vitest run` saem todos com código 0, e `.env.example` lista apenas
  `DATABASE_URL`, `REDIS_URL`, `DEVISE_JWT_SECRET_KEY`, `APP_NAME` e as
  credenciais do Google (§Ambas as suítes — entrega o caminho de CI que
  `delivery-and-observability` conecta sem redescobrir os passos).
