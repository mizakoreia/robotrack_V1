# EXECUCAO — identity-and-auth

Mapa de execução das 33 tarefas de `tasks.md`, quebradas em **grupos coerentes**,
um grupo por invocação. Cada grupo é aplicado, verificado e commitado
isoladamente antes do seguinte começar. Mesmo método de
`seal-template-baseline/EXECUCAO.md` (Onda 0) e `workspace-tenancy/EXECUCAO.md`
(Onda 1).

Este arquivo é escrito **antes** de qualquer código, de propósito: a sessão já
caiu por limite de uso uma vez. Se cair de novo, o próximo agente retoma daqui —
o mapa, o estado esperado das suítes por grupo, as armadilhas já descobertas e as
decisões de ambiente estão todos abaixo.

## Ponto de partida

- Branch: `identity-and-auth`, criada de `workspace-tenancy` (onde o trabalho da
  Onda 1 vive; a `main` não tem nada disso). **Sem push** — não há credencial.
- Baseline das suítes (antes de tocar em código, medido em 20/07/2026, rodando
  como `robotrack_app`): **backend 142 exemplos / 0 falhas**, **frontend 11
  testes / 0 falhas**.
- Pré-requisitos de `seal-template-baseline` satisfeitos: `X-Skip-Auth` vedado no
  backend (marcador interno no front, nunca trafega), magic-link removido dos dois
  lados, `spec/factories/users.rb` presente, helper `RequestAuthHelper`.
- Dois papéis de banco de `workspace-tenancy` **continuam valendo**: runtime
  (inclusive rspec) conecta como `robotrack_app` (sem SUPERUSER/BYPASSRLS);
  migrations rodam como `robotrack_migrator`. Ver `backend/db/PROVISIONING.md`.

## O objetivo central desta change

Materializar o **piso de identidade**: senha Devise + Google OAuth por redirect,
ciclo de vida do JWT com denylist **real** (logout que invalida de verdade), nome
de exibição sempre presente, e a superfície HTTP de auth com sua proteção. O
frontend ganha a tela única `/entrar`, a fonte única do token no cliente, e o
ciclo do token de convite que sobrevive ao redirect do Google.

> **Fronteira com `workspace-tenancy`:** aqui só existe `User`. O bootstrap do
> workspace no primeiro login (`Workspaces::BootstrapService`) e a `Person` são de
> `workspace-tenancy`, já implementados na Onda 1. **Não** reabrimos aquilo. O
> gancho de "chamar o bootstrap no primeiro login" que a Onda 1 deixou pendente é
> do lado de quem tem `current_user` — ele já existe; esta change apenas garante
> que o `current_user` passe a existir de verdade via senha/Google. O aceite do
> convite no servidor é de `workspace-invitations`; aqui o token é string opaca.

## Critério de agrupamento

`tasks.md` tem 6 seções, mas a ordem de dependência **real** não é 1:1 com elas:
os specs de request que verificam as seções 2 e 3 (o ciclo completo de sessão em
2.6, o OAuth em 3.4) **precisam dos endpoints Grape que a seção 4 cria** (4.1).
Aplicar seção a seção deixaria a suíte vermelha por motivo certo em G2 — o mesmo
problema que `workspace-tenancy` resolveu fundindo `Tenant.with` + allowlist na
mesma leva. Portanto:

- **Seções 2 e 4 viram um só grupo** (G2): a superfície HTTP de senha e o ciclo de
  vida do token são um circuito único. O spec de ciclo completo (2.6) e o de
  superfície negativa (4.5) não ficam verdes sem os endpoints (4.1). A allowlist
  (4.2) é **dividida**: as regex de `session`/`registration` entram em G2, a de
  `google_oauth2` entra em G3, cada grupo atualizando o `auth_route_sweep_spec`
  junto.
- As demais seções mantêm a fronteira: G1 = seção 1, G3 = seção 3, G4 = seção 5,
  G5 = seção 6.

A independência entre grupos é *sequencial*, não *paralela*: cada grupo parte de
uma base sã e entrega outra base sã. G1→G2→…→G5, sem paralelismo.

## Mapa de grupos

| Grupo | Área | Tarefas | Lado | Depende de |
|---|---|---|---|---|
| **G1** | Esquema e modelo de identidade (`User` Devise, CHECKs, migrations) | 1.1–1.5 | back | baseline |
| **G2** | Sessão JWT, denylist, superfície de senha e proteção | 2.1–2.6, 4.1–4.5 | back | G1 |
| **G3** | Google OAuth por redirect (vínculo por e-mail verificado, `#fragment`) | 3.1–3.4 | back | G2 |
| **G4** | Tela única de login e cadastro `/entrar` | 5.1–5.5 | front | G3 |
| **G5** | Sessão no cliente e ciclo do token de convite | 6.1–6.8 | front | G4 |

Total: 33 tarefas em 5 grupos.

## Decisões de autenticação já registradas na change (não reabrir)

A change **adota senha** (`database_authenticatable`, mínimo 6) **e** Google OAuth
por redirect; **descarta** o magic-link (já removido pela Onda 0). Isto está em
`proposal.md` (What Changes) e `design.md` (D4.1–D4.9). Sigo a change; não
reabro a decisão de autenticação.

Pontos que a change fixa e que guio a implementação por eles:

- **D4.1** — revogação por `Denylist` (não `JTIMatcher`): `users.jti` e seu índice
  saem; `jwt_denylist.jti` ganha índice **único**. Logout invalida só o token
  apresentado; token B do mesmo usuário sobrevive.
- **D4.2** — `exp` amarrado a `remember_me`: 30 dias marcado, 12h desmarcado,
  carimbado em `User#jwt_payload` a partir do parâmetro, não pelo
  `jwt.expiration_time` global.
- **D4.3** — renovação explícita por `POST /auth/v1/session/renew`, rotaciona o
  `jti`, com teto absoluto em `iat_origin + 2 × TTL`. **Nenhuma** renovação
  transparente em interceptor: 401 encerra a sessão.
- **D4.4** — Google é redirect de página inteira; token entregue por **fragmento**
  (`#access_token=…`), nunca query string; convite vive em `sessionStorage`.
- **D4.5** — e-mail é a chave: Google **vincula** a conta local existente por
  e-mail **verificado**, nunca duplica `User`.
- **D4.6** — nome obrigatório e normalizado, imposto por **CHECK**
  `char_length(btrim(name)) >= 2`, não só validação de model.
- **D4.7** — senha mínima 6 + CHECK `provider IS NOT NULL OR encrypted_password
  <> ''` + rack-attack (10/5min por IP+e-mail) + hash executado no caminho
  negativo para não vazar existência de conta.
- **D4.8** — allowlist pública **ancorada**: `^/auth/v1/session/?$` (não casa
  `session/renew`), `^/auth/v1/registration/?$`, `^/users/auth/google_oauth2`.
- **D4.9** — fonte única do token no cliente (`authStore` com `storage` injetado);
  `lib/api/client.ts` lê de `useAuthStore.getState()`, nunca de `localStorage`.
- **Token identifica, não autoriza** (spec `identity-and-auth`): payload = exatamente
  `sub, jti, exp, iat, iat_origin` — sem `workspace_id`, sem `role`.

## Armadilhas já descobertas (o mapa mais valioso deste arquivo)

1. **A factory base cria usuário SEM senha — o CHECK de credencial (D4.7)
   quebraria toda a suíte a jusante.** `spec/factories/users.rb` hoje cria `:user`
   sem `password` e sem `provider`. Com o CHECK `provider IS NOT NULL OR
   encrypted_password <> ''`, esse usuário viola a constraint e **todo** spec que
   faz `create(:user, …)` (tenancy, user_type_gate, error_response) vai vermelho.
   **Mitigação (G1, mesma leva do CHECK):** a factory base passa a definir
   `password` por padrão (`encrypted_password` preenchido → CHECK ok); o trait
   `:google_only` zera a senha e põe `provider`/`provider_uid`; o trait
   `:with_password` é explícito para legibilidade dos specs de senha.

2. **O `before` de `api/root.rb` tem um fallback de decode que ignora o
   denylist.** Hoje: tenta `env['warden'].authenticate` (que respeita a revogação);
   se `nil`, cai para `Warden::JWTAuth::TokenDecoder` **sem** checar denylist →
   um token revogado, ainda com assinatura válida, seria ressuscitado e o spec de
   logout (2.6) seria teatro. **Mitigação (G2):** o caminho de fallback passa a
   respeitar a revogação (checar `jwt_denylist` por `jti`, ou remover o fallback
   para a superfície de auth). A verificação honesta é: logout → `GET
   /auth/v1/me` com o mesmo token → 401.

3. **`auth_route_sweep_spec.rb` asserta `PUBLIC_ROUTES.size == 4` e o conteúdo
   exato.** Qualquer mudança em `PUBLIC_ROUTES` **exige** atualizar esse spec no
   mesmo grupo. G2 adiciona `session`/`registration` (e remove/rearranja); G3
   troca a superfície OAuth legada por `google_oauth2`. A varredura enumera só
   `Api::Root.routes` (Grape) — as rotas OmniAuth (`/users/auth/google_oauth2`)
   são rotas **Rails** via `devise_for`, não entram na varredura; a entrada na
   allowlist para elas é defensiva.

4. **`magic_login_removal_spec.rb` (Onda 0) asserta `GET /auth/v1/oauth/google_url
   → 200`.** Esse endpoint é a OAuth **manual legada** (troca de code no
   servidor). G3 a substitui pelo redirect Devise OmniAuth e **remove** o
   `oauth.rb` legado. O spec da Onda 0 precisa ser atualizado para a nova
   realidade (o Google continua de pé, agora via `/users/auth/google_oauth2`) —
   modificar spec de onda anterior é legítimo aqui porque esta change é a **dona**
   do rework de OAuth (proposal §What Changes).

5. **O token tem de ser despachado pelo Warden, não forjado à mão (4.4).** O
   `RequestAuthHelper` hoje usa `Auth::TokenService.generate_tokens`. Os specs
   existentes chamam `auth_headers(user)` e `auth_headers(user, expired: true)`.
   O helper é reescrito para despachar via Warden (`sign_in_as`), mas **mantém**
   `auth_headers`/`expired:` funcionando para não quebrar `user_type_gate_spec`,
   `error_response_spec` e os specs de tenancy. Um helper que forja o JWT faria os
   testes de denylist passarem sem a revogação funcionar.

6. **Duas superfícies de auth paralelas no front.** `lib/api/endpoints.ts`
   (`authApi`) e `lib/api/auth.ts` (`authService`) coexistem, com contratos de
   logout divergentes (POST vs DELETE). G4/G5 reconciliam numa só. Os testes
   `auth.test.ts` e `client.refresh.test.ts` verificam a superfície atual e serão
   **reescritos** — em especial `client.refresh.test.ts`, que testa o interceptor
   de refresh single-flight que D4.3 **substitui** por "401 encerra a sessão".

7. **`queryClient` é criado em `main.tsx` e não é exportado.** O logout (6.7)
   precisa de `queryClient.clear()`. G5 move a criação para um módulo compartilhado
   (ou exporta) para o logout esvaziar o cache.

8. **Colunas legadas de cartão de crédito ainda existem em `users`.** Fora do
   escopo desta change removê-las (é limpeza do domínio de cobrança). O que esta
   change faz é a **entidade** `Api::Entities::User` expor só `id, name, email,
   avatar_url` — nunca as colunas de cartão (4.1).

## Decisões de ambiente (herdadas de `workspace-tenancy`, sem regressão)

A conexão de runtime continua `robotrack_app` (sem SUPERUSER/BYPASSRLS); a RLS
continua **forçada**; os specs de isolamento de tenancy continuam verdes. Nenhuma
tarefa desta change mexe em papel de banco. As migrations de `users`/`jwt_denylist`
rodam como `robotrack_migrator`, contra dev **e** test, e só então a suíte roda
como `app`:

```bash
export PATH="$HOME/.rbenv/shims:$PATH"
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"

RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate   # gera structure.sql
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate   # sincroniza o test DB
bundle exec rspec                                                          # roda como robotrack_app
```

`jwt_denylist` é tabela serial não-tenant, já transferida ao `robotrack_app` por
`db/roles.sql` (necessário para o `TRUNCATE ... RESTART IDENTITY` da truncation).
A migration destrutiva de `users` (1.3) é reversível (`up`/`down`) e precedida do
dump lógico (1.1).

## Protocolo por grupo

1. Aplicar as tarefas do grupo (migrations como `migrator`, código, specs).
2. `bundle exec rspec` (backend, como `robotrack_app`) e, quando o grupo tocar o
   front, `npx vitest run`. Comparar com o estado esperado abaixo.
3. Marcar `- [ ]` → `- [x]` em `tasks.md` para as tarefas do grupo.
4. `npx --yes @fission-ai/openspec@1.6.0 validate identity-and-auth --strict`.
5. Commit local descrevendo o grupo. **Nenhum push.**
6. Conferir que nenhum `.env` real entrou (`**/*.env` no `.gitignore`); nenhum
   dump de banco em commit (`backend/tmp/` gitignored).

## Estado esperado da suíte por grupo

| Após | Backend (rspec, como `robotrack_app`) | Frontend (vitest) |
|---|---|---|
| Baseline | 142 / 0 | 11 / 0 |
| G1 | 142 (herdados, factory ajustada) + specs de model/CHECK/normalização verdes | inalterado |
| G2 | + ciclo de sessão/denylist/renew + superfície negativa + rate-limit verdes | inalterado |
| G3 | + specs de Google OAuth (criação/vínculo/e-mail não verificado/`#fragment`) verdes; sweep atualizado | inalterado |
| G4 | inalterado | + testes da tela `/entrar` verdes |
| G5 | inalterado | + testes de sessão/convite/logout; `client.refresh` reescrito verde |
| Alvo final | 0 falhas | 0 falhas |

## Comandos de CLI de apoio

```bash
npx --yes @fission-ai/openspec@1.6.0 validate identity-and-auth --strict
npx --yes @fission-ai/openspec@1.6.0 show     identity-and-auth --json --deltas-only
```

O CLI é a fonte da verdade sobre artefatos e validação; o recorte em G1..G5 é a
camada desta execução, registrada aqui.

## Ajustes de ambiente que apareceram na execução (não previstos no plano)

- **G1 — posse de tabela do template vs. DDL do migrator.** `users` nascia do
  `robotrack_user` e `jwt_denylist` do `robotrack_app`; nenhuma era do migrator, e
  esta onda faz DDL nas duas (a Onda 1 só CREATE'ava tabelas novas). Resolução em
  `db/roles.sql`: `users` → migrator (não tem RLS nem sequence, inócuo); `jwt_denylist`
  **continua** do app (a truncation emite `TRUNCATE ... RESTART IDENTITY`, hardcoded
  no database_cleaner 2.2.2, que exige posse da sequence "linked" à tabela) e o
  migrator vira **membro do app** (`GRANT robotrack_app TO robotrack_migrator`) para
  fazer DDL sobre tabelas do app pela via de ownership-por-membership. A RLS não é
  tocada: o runtime segue como `robotrack_app` sem BYPASSRLS; a membership é
  migrator→app, não o contrário. Tentativas descartadas: separar a posse da sequence
  (impossível — sequence "linked" segue a tabela) e `reset_ids: false` (o caminho
  postgres da truncation ignora a opção e sempre emite `RESTART IDENTITY`).
- **G1 — `jwt_authenticatable` + model `JwtDenylist` puxados para G1.** A tarefa 1.4
  liga `:jwt_authenticatable` no `User`, que exige `jwt_revocation_strategy` definida
  no carregamento do model. Por isso o model `JwtDenylist` (planejado em 2.1) veio
  para G1 — sem ele o boot quebraria. A CONFIG de dispatch/revogação no initializer
  do Devise + os endpoints continuam em G2.
- **G1 — `belongs_to :user_type, optional: true`.** O `belongs_to` do Rails exige a
  associação por padrão; com `user_type_id` nullable e o cadastro por senha sem
  preenchê-la, a associação passa a opcional (senão `POST /registration` estouraria).
- **G1 — specs de ondas anteriores ajustados pela nova invariante.** O CHECK de nome
  mín. 2 tornou impossível criar usuário com nome vazio: `bootstrap_and_resolve_spec`
  passou a simular `display_name` vazio por stub (não por `update_column`), e
  `magic_login_removal_spec` passou a criar usuário com senha (CHECK de credencial).

## Progresso

- [x] G1 — Esquema e modelo de identidade (1.1–1.5) — backend 151/0 (142 + 9 novos)
- [ ] G2 — Sessão JWT, denylist, superfície de senha e proteção (2.1–2.6, 4.1–4.5)
- [ ] G3 — Google OAuth por redirect (3.1–3.4)
- [ ] G4 — Tela única de login e cadastro (5.1–5.5)
- [ ] G5 — Sessão no cliente e ciclo do token de convite (6.1–6.8)
