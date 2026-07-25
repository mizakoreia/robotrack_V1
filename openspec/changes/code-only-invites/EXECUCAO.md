# EXECUCAO — code-only-invites

> **Status: G0 PLANEJAMENTO.** Change materializada (proposal/design/specs/tasks) e
> validada `--strict`. **Nenhum código de produção escrito.** Aguarda o dono confirmar
> DA-1 (convites já criados) e DA-2 (profundidade) antes do G1.

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

## Decisões em aberto (bloqueiam G1)

- **DA-1** — convites pendentes só-link: (a) drenar [recomendado] / (b) re-emitir / (c)
  janela de graça.
- **DA-2** — profundidade: (A) UI-only / (B) remover rota+endpoints [recomendado] / (C) B +
  dropar coluna.

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
