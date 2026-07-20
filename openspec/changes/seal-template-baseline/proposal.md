# Vedar e reduzir o template ai9 à base do RoboTrack

## Why

O repositório não é um projeto novo: é o template **ai9** renomeado. Ele carrega
três módulos de produto que não têm nenhuma relação com o RoboTrack
(WhatsApp/Evolution, Leads/Operations, Cobrança/Asaas + RBAC por planos), um
esquema de autenticação que a **D4** já decidiu descartar (magic-link de 6
dígitos), e três defeitos que impedem qualquer trabalho a jusante:

1. **`X-Skip-Auth: 1` desliga a autenticação inteira.** Está em
   `backend/app/controllers/api/root.rb:15` — é a primeira linha do bloco
   `before`, antes até da allowlist de rotas públicas. Qualquer requisição com
   esse header entra sem token. Enquanto isso existir, nenhuma prova de
   autorização (`authorization-policies`) e nenhuma prova de isolamento entre
   tenants (`workspace-tenancy`, §4.1 invariantes 1–8) tem valor: o teste
   negativo é falsificável por um header.
2. **ActionCable aceita conexão anônima.**
   `backend/app/channels/application_cable/connection.rb:9` faz
   `self.current_user = user if user.present?` e **nunca chama
   `reject_unauthorized_connection`**. Uma conexão sem `?token=` é estabelecida
   com `current_user = nil`. `DashboardChannel` e `WhatsappInstanceChannel` não
   checam `current_user` — dão stream a qualquer um. O `WorkspaceChannel` da
   **D6** herdaria essa porta aberta.
3. **A suíte não roda e a API não sobe sob erro.**
   `ExceptionNotifier.notify_exception` é chamado em `root.rb:118` sem a gem no
   `Gemfile` → todo `rescue_from` vira `NameError`. Dez tabelas do `schema.rb`
   (`plans`, `purchases`, `subscriptions`, `orders`, `order_items`, `items`,
   `categories`, `plan_features`, `plan_feature_assignments`,
   `plan_feature_permissions`) **não têm arquivo de migration** e não têm model
   — `AnalyticsService` e `PermissionsSyncService` explodem em runtime. No
   frontend, cinco arquivos de teste importam páginas inexistentes
   (`CheckoutPage`, `AdminPlansPage`, `AdminFeaturesPage`, `PaymentsPage`).

Há ainda um vazamento que o briefing não listou e que é pior que branding:
`root.rb:123` faz `error!(error_backtrace)` — **o backtrace completo do servidor
é serializado na resposta HTTP ao cliente**, com a string "POLEMK WHATS" junto.

Esta mudança é a **Onda 0** do grafo de dependências. Ela não entrega nenhum
comportamento da `ESPECIFICACAO.md`; ela torna verificável tudo que vem depois.

## What Changes

- **BREAKING** — Remoção do header `X-Skip-Auth` e do fallback de autenticação
  por `ClientApplication`. Toda rota fora da allowlist explícita passa a exigir
  `Authorization: Bearer` válido, sem exceção.
- **BREAKING** — `ApplicationCable::Connection` passa a chamar
  `reject_unauthorized_connection` quando não há usuário resolvido. Os quatro
  canais legados (`dashboard`, `lead_chat`, `permissions`, `whatsapp_instance`)
  são removidos.
- **BREAKING** — Remoção completa dos módulos **Cobrança/Asaas** (`/auth/v1/checkout`,
  `AnalyticsService`, entities `purchase`/`sale`, 10 tabelas órfãs),
  **RBAC por planos** (`/api/v1/permissions`, 4 models, 4 tabelas),
  **Leads/Operations** (`/api/v1/leads`, `/api/v1/operations`,
  `/api/v1/lead_messages`, 3 models, 3 tabelas) e
  **WhatsApp/Evolution** (`/whats/v1/*`, 4 models `Polemk*`, `EvolutionConnection`,
  4 tabelas).
- **BREAKING** — Remoção do magic-login de 6 dígitos (D4): endpoints
  `/auth/v1/magic_login/*`, `/auth/v1/code_validation`, `/auth/v1/pre_register`,
  `/auth/v1/verify_code`, `/auth/v1/complete_registration`, models `LoginCode` e
  `LoginAttempt`, `Auth::MagicLoginService`, `Auth::CodeValidationService`,
  `Auth::PreRegisterService`, `Auth::VerifyCodeService`,
  `Auth::CompleteRegistrationService`, os helpers de rate-limit em
  `api/auth/v1/base.rb`, e as telas React correspondentes.
- Remoção dos arquivos órfãos da raiz do repo: `asaas_payment_webhook_service.rb`,
  `asaas_webhook_service.rb`, `webhooks.rb`.
- `ExceptionNotifier` substituído por um reporter fino sobre `Rails.error`, sem
  adicionar gem.
- Respostas de erro 5xx deixam de conter backtrace; passam a `{ error, message,
  request_id }` com o backtrace apenas no log estruturado.
- Rebranding: "POLEMK WHATS" / "Polemk API" → "RoboTrack" em mensagens, swagger e
  seeds.
- Criação de `backend/spec/factories/`, de `spec/support/request_auth_helper.rb`
  (substituindo os `bearer_for` duplicados em cada spec) e da configuração de
  `database_cleaner-active_record`.
- Suíte verde nos dois lados: backend `rspec` e frontend `vitest` terminam com 0
  falhas e 0 arquivos com erro de importação.

### Não-objetivos

- **Não** implementar `database_authenticatable`, senha, denylist real de JWT ou
  Google redirect — isso é `identity-and-auth` (D4). Esta mudança apenas **remove**
  o que ocupa o lugar e deixa `omniauth` funcionando como está.
- **Não** criar `Workspace`, `Person`, `Membership`, `workspace_id` ou RLS — é
  `workspace-tenancy` (D2, D10).
- **Não** criar policies nem o route-sweep spec — é `authorization-policies` (D3).
  Aqui, a allowlist de rotas públicas é declarada num único ponto **para que**
  aquele sweep tenha onde ancorar.
- **Não** desenhar o `WorkspaceChannel` — é `realtime-collaboration` (D6). Aqui só
  se veda a conexão.
- **Não** resolver as duplicações de biblioteca do frontend (charts à mão vs.
  Recharts, TipTap vs. Slate) nem substituir o padrão `useEffect + apiClient` por
  React Query — é `design-system` e D9 (`app-shell-navigation`).
- **Não** configurar Sentry/APM/pipeline de deploy — é `delivery-and-observability`;
  esta mudança expõe o ponto de plugagem (`ErrorReporter`) e nada mais.
- **Não** remover `UserType` / `User#og?` / `#client?`: `workspace-tenancy` os
  substitui por `Membership.role`. Removê-los aqui derrubaria o único gate de
  autorização existente antes de haver substituto.

## Capabilities

### New Capabilities

- `template-security-hardening`: fechamento dos bypasses de autenticação do
  template — header `X-Skip-Auth`, fallback por `ClientApplication`, conexão
  ActionCable anônima — e saneamento do caminho de erro (sem backtrace na
  resposta, sem `ExceptionNotifier` fantasma).
- `template-scope-reduction`: remoção ordenada e reversível dos módulos que não
  pertencem ao RoboTrack (cobrança, RBAC por planos, leads, WhatsApp/Evolution,
  magic-login), dos arquivos órfãos da raiz e do branding herdado, incluindo o
  descarte das tabelas correspondentes com backup obrigatório.
- `test-harness-baseline`: infraestrutura de teste utilizável — factories,
  helper de autenticação de request compartilhado, estratégia de limpeza de
  banco — e as duas suítes (RSpec e Vitest) verdes e executáveis em CI.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio: nada foi construído ainda.

## Impact

- **Código**: `backend/app/` perde ~40 arquivos (13 models, 12 services, 15
  endpoints/entities, 4 channels); `backend/db/schema.rb` perde 21 tabelas;
  `frontend/src/` perde 3 páginas, 4 módulos de `features/auth` e 6 arquivos de
  teste.
- **Contrato de API**: a superfície pública cai de ~40 endpoints para
  `/auth/v1/oauth/*`, `/auth/v1/sessions/*`, `/auth/v1/me`, `/api/v1/users`,
  `/api/v1/uploads`, `/api/v1/countries`, `/api/v1/downloads` e `/swagger_doc`.
- **Dados**: descarte de 21 tabelas. Como o ambiente é pré-produção, o risco é
  perder o dataset de desenvolvimento — daí a exigência de dump antes de cada
  migration destrutiva.
- **Downstream**: desbloqueia `workspace-tenancy` e `identity-and-auth` (Onda 1)
  e, por transitividade, todo o caminho crítico.
- **Entrega**: `delivery-and-observability` recebe o `ErrorReporter` como ponto de
  integração e herda a responsabilidade das env vars de e-mail/Redis que
  deixam de ser exigidas pelo magic-login.
