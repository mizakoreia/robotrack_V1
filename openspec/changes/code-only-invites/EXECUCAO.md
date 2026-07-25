# EXECUCAO — code-only-invites

> **Status: EM EXECUÇÃO.** Decisões FIXADAS pelo dono (não mais pendentes):
> **DA-2 = opção B** (remover rota pública `/convite/:token` + endpoints preview/accept
> por token + `invite_url`; código vira o único localizador; coluna `token` DORMENTE,
> sem migração destrutiva). **DA-1 = drenar/reemitir** os convites pendentes ANTES do
> merge, para ninguém ficar sem caminho (rake/procedimento documentado — G3).

## Mapa de grupos

| Grupo | Entrega | Verificação |
|---|---|---|
| G0 | Reconciliação + esqueleto OpenSpec + este EXECUCAO | `validate --strict` verde |
| G1 | Backend: remover endpoints/allowlist por token; serviço só por código | request specs code/* verdes, specs de token removidos, route-sweep/cross-tenant verdes |
| G2 | Frontend: remover link do `InviteDialog`/`TeamPanel`, rota `/convite/:token`, ramo de token no cliente | `vitest`/`tsc`/`lint` verdes |
| G3 | E2E código-só + documentação no mesmo empurrão | `e2e:lint` + `validate --strict` verdes |
| G4 | Fechamento + resumo ao dono | — |

## Reconciliação design × realidade (levantada no planejamento)

O que EXISTE e SAI (mapeado com paths):

- **Frontend link:** `InviteDialog.tsx` L92–104 (região do link), L58–72 (`copiar()`),
  L129–131 ("Copiar link"); `TeamPanel.tsx` L227–233 (input `invite_url`); `InviteRoute.tsx`
  + `App.tsx:52` (rota `/convite/:token`); `session.ts` L38–96 (`consumeInvite` token),
  L196–209 (`handleInviteAfterAuth` ramo token); `invite.ts` (`INVITE_KEY`); DTO `invite_url`
  em `endpoints.ts`.
- **Backend link:** `invitation_tokens.rb` L82–87 (`GET ':token'`), L96–108 (`POST
  ':token/accept'`); `AcceptService`/`PreviewService` (ramos de token); entity `invite_url`
  (`AppUrl.invite_url`); `root.rb` `PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES` + `public_routes.yml`.

O que FICA (código-só reusa, não tocar): seção "Tenho um código" da `AuthPage`,
`JoinByCodeDialog`, `consumeInviteByCode`, `namespace :code` (preview/accept), model
`row_by_code`/`invitation_by_code`, lockout/rate-limit do código.

## Decisões (recomendadas — G0)

- **D1 (profundidade):** remover rota pública + endpoints por token (não UI-only).
  RECOMENDADO; pende DA-2.
- **D2 (banco):** manter `token`/`invitation_by_token`/ramo de RLS **dormentes**, sem
  migração destrutiva. RECOMENDADO.
- **D3:** aceite continua atômico e por e-mail; muda só o localizador (código).
- **D4:** a allowlist pública **encolhe** — exceção consciente à regra "só cresce",
  registrada; route-sweep segue verde (rota e allowlist saem juntas).
- **D5/DA-1:** convites já criados que só têm link entregue — decisão de operação do dono.

## Decisões FIXADAS pelo dono

- **DA-1** — convites pendentes só-link: **drenar/reemitir antes do merge**. Como todo
  convite pendente já tem código no banco (invite-by-code), a reemissão é recuperar o código
  do pendente; um rake/procedimento documentado (G3) garante que nenhum pendente fica sem
  caminho. Nada é enviado automaticamente — o dono passa o código.
- **DA-2** — profundidade: **opção B** (remover rota + endpoints por token; coluna dormente,
  sem migração destrutiva).

## G1 — resultado (backend, VERDE)

- **Produção:** `invitation_tokens.rb` (removidas `GET ':token'` + `POST ':token/accept'`,
  `namespace :code` intacto); `accept_service.rb`/`preview_service.rb` (construtor só
  `code:`/`email:`, `lookup_by_token`/`lookup` removidos, `workspace_matches?` simplificado —
  não há mais `X-Workspace-Id` no aceite); entity sem `invite_url`; `AppUrl.invite_url`
  removido (`base` fica — guarda de boot); `root.rb` sem as entradas de token em
  `PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES`; `public_routes.yml` sem a linha do token.
- **Specs:** superfície convite+autorização+tenancy = **549 exemplos, 0 falhas, 8 pending**.
  Reescritos token→código: `accept_spec`, `end_to_end_spec`, `concurrent_accept_spec`,
  `invariants_spec`, `inv_6_invite_single_use_spec`, `identity_precondition_spec`,
  `team_panel_spec`, `create_spec`, `code_flow_spec`, `app_url_spec`, `code_lockout_spec`,
  `auth_route_sweep_spec`. `rate_limit_spec.rb` (token) **removido** — coberto por
  `code_rate_limit_spec.rb`.
- **Decisão de execução DE-1:** o cenário `workspace_alheio` (X-Workspace-Id divergente →
  `invitation_workspace_mismatch`) foi **dropado** dos specs: o aceite por código é
  tenant-exempt e não recebe `X-Workspace-Id`, então a condição 4 do `validate!` vira defesa
  ESTRUTURAL inalcançável por HTTP. O erro e sua tradução ficam (custo zero); os "seis
  cenários" viraram cinco, todos com código distinto.

## G2 — resultado (frontend, VERDE)

- **Produção:** `InviteDialog` (success view code-first, sem link/`copiar()`);
  `TeamPanel/LinhaConvite` (sem input `invite_url`); `App.tsx` sem a rota `/convite/:token`;
  `InviteRoute.tsx` + seu teste **removidos**; `session.ts` sem `consumeInvite`/
  `emailMascaradoDoConvite` e sem o ramo de token em `handleInviteAfterAuth`; `invite.ts`
  sem `INVITE_KEY`/capture/read/clear (só o par código); `endpoints.ts` DTO sem `invite_url`,
  sem `preview(token)`/`accept(token)`; i18n reescrito (link → código) e chaves de link
  mortas removidas.
- **Gates:** `tsc`/`lint` limpos; `vitest` de convite **74/74**; suíte inteira 575/576.
- **Flaky pré-existente (NÃO é regressão):** `src/lib/offline/__tests__/queue.test.ts`
  "a 501ª é REJEITADA (D7-12)" falha só sob paralelismo da suíte cheia e **passa isolado**
  (8/8). É `offline-pwa` (IndexedDB/timing), domínio intocado por esta change.

## Armadilhas previstas

- **Ordem de rota:** o `namespace :code` foi declarado ANTES de `:token` de propósito
  (senão `code/accept` casaria `:token/accept` com `token="code"`). Ao remover `:token`, a
  precaução perde a razão de ser, mas confira que nada mais casa por engano.
- **Model `validates :token, presence` + `assign_token on: :create`:** com a coluna dormente
  (D2), seguem gerando token nunca exposto — OK. Só um corte de coluna os removeria.
- **Testes que cobrem token:** request specs de preview/accept por token, sweeps de rota
  pública e o trecho de link do e2e `invite-code.spec` precisam ser removidos/reescritos —
  senão a suíte cobre rota inexistente e fica vermelha.
- **`AppUrl.invite_url`:** confirmar que nenhum outro lugar (e-mail, notificação) o usa antes
  de remover.
