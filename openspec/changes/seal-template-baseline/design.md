# Design — seal-template-baseline

## Context

O repositório é o template ai9 com `Robotrack::Application` no lugar do nome
antigo. Nada mais foi trocado. O estado real, verificado no código:

**Autenticação.** `backend/app/controllers/api/root.rb` tem um único bloco
`before` com três saídas antes de qualquer verificação:

```ruby
skip_header = (headers['X-Skip-Auth'] == '1') || (headers['HTTP_X_SKIP_AUTH'] == '1')
next if skip_header
```

Depois disso vem uma allowlist de 18 regex, e no fim um fallback: se o token não
resolve para um `User`, tenta `ClientApplication.active.find_by(token:)` e, se
achar, deixa passar com `env['api.current_client']` — sem usuário, sem escopo,
sem expiração. São **dois** bypasses, não um.

**Realtime.** `ApplicationCable::Connection#connect` resolve o usuário por
`request.params[:token]` e faz `self.current_user = user if user.present?`.
Não há `else`, não há `reject_unauthorized_connection`. Conexão sem token é
aceita. `DashboardChannel#subscribed` faz `stream_for("dashboard:kpis")`
incondicionalmente; `WhatsappInstanceChannel` idem, e tem um
`can_access_instance?` que retorna `true` literal. Só `LeadChatChannel` checa
(`current_user&.og?`).

**Caminho de erro.** `root.rb:118` chama `ExceptionNotifier.notify_exception` —
gem ausente do `Gemfile`, logo `NameError` dentro do `rescue_from :all`. E
`root.rb:123` faz `error!(error_backtrace)` onde `error_backtrace` é
`"ERROR - API POLEMK WHATS: #{e.message} ... BACKTRACE: #{e.backtrace.join}"`.
O backtrace inteiro vai no corpo da resposta HTTP. `api/v1/base.rb` e
`api/auth/v1/base.rb` têm cópias do mesmo `rescue_from` (a de `auth` monta o
`env` do notifier e **nunca o usa** — código morto).

**Esquema.** `db/schema.rb` declara 31 tabelas. `db/migrate/` tem 20 arquivos.
Dez tabelas — `plans`, `plan_features`, `plan_feature_assignments`,
`plan_feature_permissions`, `purchases`, `subscriptions`, `orders`,
`order_items`, `items`, `categories` — **existem no schema e não têm migration
nem model**. `rails db:migrate` a partir do zero não reproduz `db/schema.rb`. É
drift, não dívida ordinária.

**Acoplamento entre os módulos a remover** (medido por grep, não presumido):

```
AnalyticsService ────────► Purchase, Subscription, Lead
PermissionsSyncService ──► Purchase, Plan
Auth::CheckoutSessionService ► Purchase, Subscription
ApplicationCable::Connection#allow_public_checkout_subscription? ► Purchase
Api::V1::Permissions ────► Plan
Lead / LeadMessage ──────► Operation
LeadCrossChannelService ─► PolemkInstance, EvolutionConnection
WhatsAppWebhookService ──► Lead   (o webhook do WhatsApp CRIA leads)
Api::Auth::V1::Base (helpers) ► LoginAttempt, LoginCode
User ────────────────────► login_codes, login_attempts (has_many)
```

Isso define a ordem: **consumidores antes de produtores**. Remover `Purchase`
antes de `AnalyticsService` deixa o boot quebrado por N commits.

**Frontend.** `vitest.config.ts` existe (o `test:` está lá, não no
`vite.config.ts`). Cinco specs importam páginas que não existem no disco:
`CheckoutPage`, `AdminPlansPage`, `AdminFeaturesPage`, `PaymentsPage`; um sexto,
`HomePage.plans.test.tsx`, testa uma seção de planos da `HomePage`. Mais
`MagicLogin.test.tsx`, `CodeValidation.test.tsx` e
`useAuth.requestMagicLogin.test.tsx`, que testam o fluxo que a D4 descarta.

## Goals / Non-Goals

**Goals**

- Nenhum caminho de código permite acesso autenticado sem um JWT válido — nem
  por header, nem por token de aplicação, nem por WebSocket.
- Um teste de regressão falha se o bypass voltar, e falha por asserção sobre
  comportamento HTTP/Cable, não por `grep` no fonte.
- Boot limpo: `rails runner 'Rails.application.eager_load!'` sem `NameError`.
- `db:drop db:create db:schema:load db:seed` reproduz o ambiente do zero.
- `bundle exec rspec` e `npm test` terminam verdes, com pelo menos um teste
  substantivo em cada lado (suíte vazia não conta como verde).
- Toda remoção de tabela é precedida por um dump nomeado e restaurável.

**Non-Goals**

- Login com senha, denylist real de JWT, Google redirect (`identity-and-auth`).
- Multi-tenancy, RLS, `Person` (`workspace-tenancy`).
- Policies e route-sweep (`authorization-policies`).
- Cobertura de teste alvo. A meta aqui é **executável e honesta**, não %.

## Decisions

### D-A. O bypass morre; a allowlist vira uma constante única e testável

Remove-se o `skip_header` inteiramente. A allowlist de rotas públicas sai do
corpo do `before` e vira `Api::Root::PUBLIC_ROUTES` — um array congelado de
regex, no topo do arquivo, com a lista reduzida às rotas que sobrevivem:
`/swagger_doc`, `/api/v1/countries`, `/auth/v1/oauth/{google_url,callback}`.

*Alternativa descartada:* manter o header protegido por env var
(`ALLOW_SKIP_AUTH=1` só em teste). Descartada porque é exatamente assim que ele
chegaria em produção — uma env var num `.env` copiado. E porque o teste que
importa (isolamento entre tenants, §4.1) só vale se **não existir** uma forma de
o desligar; um bypass condicional continua sendo um bypass no binário.

*Onde a invariante mora:* no bloco `before` de `Api::Root`, que é o **único**
ponto de entrada (`config/routes.rb` monta `Api::Root => '/'` e nada mais serve
JSON). Reforço executável: um spec parametrizado que varre `Api::Root.routes`,
subtrai `PUBLIC_ROUTES`, e exige 401 em cada rota restante — com e sem
`X-Skip-Auth: 1`. Esse spec é o ancestral direto do route-sweep da D3; deixo o
formato do dado (`Api::Root.routes.map(&:pattern)`) já no lugar para que
`authorization-policies` o estenda em vez de reinventar.

### D-B. `ClientApplication` é removido, não confinado

O fallback autentica um portador de token opaco sem usuário associado, sem
expiração e sem escopo. O RoboTrack não tem requisito de integração
máquina-a-máquina em nenhuma seção da `ESPECIFICACAO.md`.

*Alternativa descartada:* manter a tabela e restringir o fallback a uma
allowlist de rotas de webhook. Descartada porque os webhooks que a justificavam
(`/whats/v1/webhooks/*`, Asaas) estão todos sendo removidos nesta mesma mudança
— sobraria um mecanismo de auth de segunda classe protegendo zero rotas, que é
uma armadilha esperando o primeiro integrador.

*Consequência:* `client_applications` entra na lista de tabelas descartadas.
Se `delivery-and-observability` precisar de um endpoint de health check
autenticado, ele declara o próprio mecanismo.

### D-C. Cable rejeita por padrão; canais legados vão embora

`find_verified_user` passa a `reject_unauthorized_connection` quando o token
está ausente, é inválido ou não resolve um `User`. Os quatro canais são
deletados junto com seus módulos.

*Alternativa descartada:* manter `DashboardChannel` como esqueleto para o
`WorkspaceChannel` da D6 herdar. Descartada porque ele carrega o hábito errado
(`stream_for` sem verificar quem pediu) e o `WorkspaceChannel` precisa
autorizar por `Membership`, que ainda não existe — um esqueleto que autoriza
nada seria copiado como se autorizasse algo.

*Onde a invariante mora:* em `Connection#connect`. É o ponto de estrangulamento
do Cable — nenhum canal é instanciado sem passar por ele, então um canal futuro
não pode esquecer de verificar identidade (só pode esquecer de verificar
**autorização**, que é problema da D3/D6). Prova: spec de `ActionCable::Connection`
com `connect "/cable"` sem token esperando `ActionCable::Connection::Authorization::UnauthorizedError`.

*Nota de entrega:* `config/cable.yml` já usa `adapter: redis` em produção
(D6 exige isso) e `adapter: test` em teste. Nada a mudar; registrado para que
`realtime-collaboration` não replaneje.

### D-D. O caminho de erro para de vazar e passa a ter um ponto de plugagem

Os três `rescue_from :all` duplicados (`api/root.rb`, `api/v1/base.rb`,
`api/auth/v1/base.rb`) colapsam num só, em `Api::Root`. Ele:

1. gera/propaga um `request_id`;
2. loga `message + backtrace` via `Rails.logger` em uma linha estruturada;
3. chama `ErrorReporter.report(e, context:)` — um módulo de ~15 linhas em
   `app/services/error_reporter.rb` que hoje só encaminha para
   `Rails.error.report`;
4. responde `{ error: 'internal_error', message: 'Erro interno no servidor',
   request_id: }` com 500. **Nunca** o backtrace.

*Alternativa descartada:* adicionar `gem 'exception_notification'`. Descartada
porque escolheria o destino de erro (e-mail SMTP) por inércia do template, e
essa escolha pertence a `delivery-and-observability`, que vai comparar
Sentry/Honeybadger/log agregado. `Rails.error` é a interface que o Rails 8 já
oferece e que qualquer um desses três se pluga por baixo sem tocar no Grape.

*Onde a invariante mora:* num spec de request que provoca uma exceção real (rota
de teste que levanta) e asserta que o corpo da resposta **não casa** com
`/BACKTRACE|\.rb:\d+|app\/services/`. Assertar "não contém backtrace" é o modo de
falha concreto; assertar "retorna 500" não pegaria a regressão.

### D-E. Ordem de remoção: consumidores → produtores → tabelas

Quatro fases, nesta ordem, cada uma deixando o boot verde:

```
Fase 1  Cobrança/Asaas   AnalyticsService, Api::V1::Analytics, entities
        (consumidores)   purchase/sale/analytics, Auth::CheckoutSessionService,
                         Api::Auth::V1::Checkout, allow_public_checkout_subscription?,
                         arquivos órfãos da raiz, frontend checkoutSession/PaymentsPage
Fase 2  RBAC por planos  PermissionsSyncService, Api::V1::Permissions,
                         PermissionsChannel, entities permission*, models
                         Permission/UserPermission/PermissionAuditLog/PermissionConflict
Fase 3  Leads → Whats    LeadChatChannel, Api::V1::{Leads,LeadMessages,Operations},
                         Lead*Service, models Lead/LeadMessage/Operation;
                         DEPOIS Api::Whats::V1::*, Polemk*Service,
                         EvolutionConnection, WhatsAppWebhookService,
                         WhatsappInstanceChannel, models Polemk*
Fase 4  Magic-login      Api::Auth::V1::{MagicLogin,CodeValidation,Registration},
                         Auth::{MagicLogin,CodeValidation,PreRegister,VerifyCode,
                         CompleteRegistration}Service, AuthMailer + views,
                         helpers de rate-limit em auth/v1/base.rb,
                         has_many de User, models LoginCode/LoginAttempt
Fase 5  Tabelas          uma migration destrutiva única (ver D-F)
```

Leads **antes** de WhatsApp porque `WhatsAppWebhookService` cria `Lead`; a
seta é `Whats → Lead`, então Lead é o produtor e sai depois? Não: aqui o
consumidor a derrubar primeiro é o endpoint `/api/v1/leads` (voltado ao
usuário), e o `WhatsAppWebhookService` some inteiro na sub-fase seguinte. A
ordem interna da Fase 3 é: endpoints de Lead → services de Lead → módulo Whats
inteiro → models de Lead → models Polemk. `Operation` sai depois de `Lead`
(`Lead belongs_to :operation`).

*Alternativa descartada:* uma remoção atômica num único commit gigante.
Descartada porque, com 40 arquivos e acoplamento cruzado, um `NameError`
residual não teria bisseção possível. Cada fase termina com
`Rails.application.eager_load!` + `rspec` verdes, então a fase seguinte parte de
uma base sã.

### D-F. Tabelas: uma migration `drop_table` única, e `schema.rb` como fonte da verdade

As 10 tabelas de cobrança não têm migration. Reconstruir a história (escrever as
migrations `create_table` que faltam só para depois escrever os `drop_table`) é
trabalho puro de arqueologia.

*Decisão:* uma única migration
`RemoveTemplateTables` com `drop_table ..., force: :cascade` para as 21 tabelas,
escrita com `def up` e um `def down` que levanta
`ActiveRecord::IrreversibleMigration` **com a mensagem apontando o arquivo de
dump**. O caminho de rollback é o dump `pg_restore`, não o `down`.

*Alternativa descartada:* `down` reconstruindo as tabelas. Descartada porque
um `down` que recria estrutura vazia dá falsa sensação de reversibilidade — os
dados não voltam, e é dado que se quer de volta ao reverter em dev.

*Tabelas descartadas (21):* `plans`, `plan_features`, `plan_feature_assignments`,
`plan_feature_permissions`, `purchases`, `subscriptions`, `orders`,
`order_items`, `items`, `categories`, `permissions`, `user_permissions`,
`permission_audit_logs`, `permission_conflicts`, `leads`, `lead_messages`,
`operations`, `polemk_instances`, `polemk_instance_groups`,
`polemk_chat_messages`, `polemk_webhooks`, `client_applications`.
*(São 22 com `client_applications`; a contagem de 21 exclui-a por ser da D-B.)*

*Preservadas:* `users`, `user_types`, `jwt_denylist`, `login_codes` e
`login_attempts` — as duas últimas **não**: caem na Fase 4. Preservadas de fato:
`users`, `user_types`, `jwt_denylist`, `action_text_rich_texts`,
`active_storage_*`. `jwt_denylist` fica intocada porque a D4 vai ligá-la.

*Ordem dentro da migration:* filhas antes de mães (`order_items` antes de
`orders` e `items`; `plan_feature_*` antes de `plans` e `plan_features`;
`lead_messages` antes de `leads` antes de `operations`), para que
`force: :cascade` seja rede de segurança e não o mecanismo.

### D-G. `use_transactional_fixtures` fica; `database_cleaner` entra só para o caso que ele não cobre

`spec/rails_helper.rb` já tem `use_transactional_fixtures = true`, que é rápido e
correto para 100% dos specs atuais.

*Decisão:* mantém transacional como padrão e configura
`database_cleaner-active_record` com estratégia `:truncation` acionada **apenas**
por metadado (`type: :system` ou `js: true`) — os casos em que o teste roda em
outra thread/conexão e a transação do RSpec não é visível. Um `append_after`
global de `DatabaseCleaner.clean` só nesses.

*Alternativa descartada:* truncar tudo sempre. Descartada porque multiplica o
tempo da suíte por ~5 sem resolver problema nenhum hoje, e a suíte precisa ficar
rápida — `progress-rollup` e `authorization-policies` vão adicionar specs de
dataset grande.

*Nota para `workspace-tenancy`:* quando a **D2** ligar RLS com
`SET LOCAL app.current_workspace_id`, o `SET LOCAL` morre no fim da transação —
o que interage com o `use_transactional_fixtures`. Fica registrado aqui como
handoff, não resolvido aqui.

### D-H. Frontend: os testes órfãos são deletados com a feature, não consertados

Cinco dos dez arquivos de teste testam produto que não é RoboTrack. Escrever
`CheckoutPage.tsx` para fazer o teste passar seria construir cobrança.

*Decisão:* deletar `CheckoutPage.redirect.test.tsx`, `AdminPlansPage.test.tsx`,
`AdminFeaturesPage.test.tsx`, `SalesPage.table.test.tsx`,
`HomePage.plans.test.tsx`, `MagicLogin.test.tsx`, `CodeValidation.test.tsx`,
`useAuth.requestMagicLogin.test.tsx`. Sobrevivem `campfire/hero.test.tsx` e
`lib/api/auth.test.ts` (este último podado das asserções de magic-login).

*Alternativa descartada:* `it.skip` nos órfãos. Descartada porque um `skip` é uma
suíte verde que mente — e a barra desta mudança é "verde e honesto".

*Compensação:* como isso levaria a suíte a dois arquivos, adiciona-se um spec de
`lib/api/client.ts` que exercita o interceptor de 401 com refresh single-flight
(injeta duas 401 concorrentes, asserta **um** POST de refresh e duas
retentativas). É o pedaço mais frágil e menos testado do frontend, e
`offline-pwa` vai depender dele.

### D-I. Rebranding é substituição de literal, com `APP_NAME` onde já existe

`root.rb` já lê `ENV.fetch('APP_NAME', 'robotrack')` no swagger, mas hardcoda
"POLEMK WHATS" nas mensagens de erro. `grape_swagger_rails.rb` hardcoda
"Polemk API". Como as mensagens de erro deixam de ir para o cliente (D-D), o
branding remanescente é só log e swagger — 4 arquivos.

*Não* renomear os models `Polemk*`: eles são deletados na Fase 3.

## Plano de migração

1. `pg_dump -Fc` do banco de desenvolvimento para
   `backend/tmp/backups/pre-seal-<AAAAMMDD-HHMM>.dump`, com verificação de
   restauração em um banco descartável **antes** de qualquer `drop_table`.
2. Fases 1–4 (código), cada uma verificada por `eager_load!` + `rspec`.
3. Fase 5: `RemoveTemplateTables` em desenvolvimento; regenerar `db/schema.rb`.
4. Prova do fim do drift: `db:drop && db:create && db:schema:load && db:seed`
   num banco limpo, seguido de `rspec`.
5. `db/seeds.rb` reescrito: hoje ele semeia instância WhatsApp, leads e
   lead_messages (`SEED_WHATS_INSTANCE`, `SEED_LEADS`). Fica apenas
   `UserType.seed_default_types!` + um usuário OG de desenvolvimento.
6. Não há produção. Nenhuma janela de manutenção, nenhum plano de rollback
   online — o rollback é restaurar o dump.

## Riscos / Trade-offs

- **Remover o `X-Skip-Auth` quebra o fluxo de desenvolvimento de quem o usava
  para bater na API com curl.** Mitigação: o helper de auth de request
  (`test-harness-baseline`) e um `rails runner` que imprime um JWT de dev
  substituem o caso legítimo. O caso ilegítimo é justamente o que se quer
  quebrar.
- **`AuthMailer` some junto com o magic-login, e `workspace-invitations` vai
  precisar de e-mail.** Aceito: aquela capacidade tem requisito próprio de
  template e de entregabilidade; herdar o mailer do magic-login economizaria um
  arquivo e importaria a configuração de SMTP não-decidida.
- **A migration destrutiva é irreversível por `down`.** Aceito conscientemente
  (D-F); mitigado pelo dump verificado, não meramente tirado.
- **`Api::V1::Users` depende de `User#og?`, que `workspace-tenancy` vai
  substituir por `Membership.role`.** Esta mudança preserva `og?` de propósito
  para não deixar um vão de autorização entre ondas. O custo é uma remoção
  duplicada mais adiante.
- **`AnalyticsService` some e com ele o `DashboardKpisBroadcastJob` e a
  `DashboardPage`.** A Visão Geral do RoboTrack (§3.2) não é essa tela; reusar o
  esqueleto custaria mais em desemaranhamento do que reescrever.
- **Contagem de tarefas.** Ficou em 28, no teto da faixa. O que foi deliberadamente
  deixado de fora: consolidação Recharts/charts-à-mão, TipTap/Slate,
  unificação do token entre `localStorage` e `authStore` (D9 /
  `identity-and-auth`), e a remoção de `tokens-campfire.css` (`design-system`).

## Perguntas em aberto

1. `users` tem `cpf_cnpj`, `cep`, `state`, `phone` — resíduo de cobrança. Manter
   as colunas (custo zero) ou dropar junto? **Proposta:** manter nesta mudança;
   `identity-and-auth` decide ao definir o cadastro. Dropar aqui exigiria
   reescrever `User` no meio de uma mudança que não é sobre `User`.
2. `paper_trail` está instalada e não usada. `audit-log` (§2.8) provavelmente
   **não** a usará (a spec exige append-only com `REVOKE UPDATE, DELETE`, que
   `versions` não tem). Removê-la é decisão de `audit-log`, não daqui.
3. `Api::V1::Downloads` e `Api::V1::Uploads` sobrevivem sem consumidor conhecido
   no RoboTrack. Mantidos por ora; se `commissioning-report` gerar o A4 no
   cliente, `Downloads` vira candidato a corte numa mudança futura.
