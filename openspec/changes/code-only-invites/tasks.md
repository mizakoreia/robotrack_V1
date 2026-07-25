## G0. Reconciliação e esqueleto da change

- [x] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/code-only-invites/spec.md`, `tasks.md`) reconciliando com a REALIDADE do repo (o
  que `workspace-invitations`/`invite-by-code` construíram e o que sai)
- [x] G0.2 Escrever `EXECUCAO.md` com o mapa de grupos G0..G4, as decisões (D1 profundidade,
  D2 coluna dormente, D4 allowlist encolhe) e as armadilhas previstas (testes que cobrem
  token, ordem `code/*` vs `:token`, model `validates :token`)
- [x] G0.3 Decisões FIXADAS pelo dono: DA-2 = opção B (remover rota+endpoints por token),
  DA-1 = drenar/reemitir os pendentes antes do merge — registrado no `EXECUCAO.md`
- [x] G0.4 Verificação do grupo: `npx --yes @fission-ai/openspec@1.6.0 validate
  code-only-invites --strict` verde

## G1. Backend — remover os endpoints e a superfície pública por token

- [x] G1.1 Remover `GET ':token'` (preview) e `POST ':token/accept'` (aceite) de
  `invitation_tokens.rb`, mantendo o `namespace :code` intacto
- [x] G1.2 `AcceptService`/`PreviewService`: remover os ramos de token (`lookup_by_token`/
  `lookup`); construtor deixa de aceitar `token:`; o código vira o único localizador
- [x] G1.3 Entity: parar de expor `invite_url`; remover `AppUrl.invite_url` (mantém `base`,
  usado pelo guarda de boot)
- [x] G1.4 Remover as entradas de token de `root.rb` (`PUBLIC_ROUTES`,
  `TENANT_EXEMPT_ROUTES`) e de `config/authorization/public_routes.yml` (D4 — allowlist
  encolhe, registrado)
- [x] G1.5 **Verificação:** superfície de convite+autorização+tenancy **549 exemplos, 0
  falhas, 8 pending**. Specs por token reescritos para código (`accept_spec`, `end_to_end`,
  `concurrent_accept`, `invariants`, `inv_6`, `identity_precondition`); `rate_limit_spec`
  (token) removido (coberto por `code_rate_limit_spec`); `auth_route_sweep` re-ancorado
  (token GET não é mais público, `PUBLIC_ROUTES.size == 7`); route-sweep/cross-tenant verdes
  (rota e allowlist saíram juntas). Cenário `workspace_alheio` dropado (inalcançável por
  código); `invitation_workspace_mismatch` vira defesa estrutural inalcançável por HTTP.

## G2. Frontend — remover toda a superfície de LINK

- [x] G2.1 `InviteDialog.tsx`: removida a região do link (input `invite_url`, `copiar()`,
  "Copiar link"); success view **code-first** (código + "Copiar código")
- [x] G2.2 `TeamPanel.tsx`/`LinhaConvite`: removido o input `invite_url` da lista de pendentes
- [x] G2.3 Removida a rota `/convite/:token` (`App.tsx`) e o componente `InviteRoute.tsx`
  (+ seu teste); o fluxo por código já cobre a entrada
- [x] G2.4 `session.ts`/`invite.ts`: removidos `consumeInvite`+`emailMascaradoDoConvite`
  (token), o ramo de token de `handleInviteAfterAuth`, e a chave `INVITE_KEY`
  (capture/read/clear); `endpoints.ts` DTO sem `invite_url` e sem os métodos `preview`/
  `accept` por token; i18n: `inviteSubmit`/`lostToken`/`revokeConfirm`/`inviteCodeHint`
  reescritos para código, chaves de link mortas removidas
- [x] G2.5 **Verificação:** `tsc --noEmit` e `lint` limpos; `vitest` do domínio de convite
  **74/74** (team + auth + session + api); suíte inteira 575/576 (a única falha é o teste
  flaky pré-existente de fila offline `queue.test.ts` D7-12, que passa isolado — alheio a
  esta change). Reescritos: `session.test`, `inviteCode.test`, `TeamPanel.test`,
  `invitations.i18n.test` (lista de telas sem o `InviteRoute` removido)

## G3. E2E, rake de reemissão (DA-1) e documentação

- [x] G3.1 E2E **só por código**: removido `e2e/tests/invite.spec.ts` (fluxo por link);
  `invite-code.spec.ts` promovido a Fluxo 1 (botão "Gerar código de convite"); botão
  renomeado também em `join-by-code.spec.ts`; `e2e/README.md` atualizado. `e2e:lint` **OK
  (14 specs)**. Execução em navegador é HANDOFF (não repontar :3000 sob a demo viva).
- [x] G3.2 **Rake de reemissão (DA-1):** `backend/lib/tasks/invitations.rake` —
  `invitations:reissue_codes[<workspace_id>]` gera um CÓDIGO novo para cada convite pendente
  (o claro antigo é irrecuperável — só o HMAC é guardado), renova a validade, zera o lockout
  e IMPRIME o par (e-mail, código) para o dono repassar. Nada é enviado. Spec
  `spec/invitations/reissue_codes_spec.rb` **2/2** (reemite+renova+zera+imprime; não toca
  usados/expirados). Procedimento de drenagem ANTES do merge.
- [x] G3.3 **Verificação:** `openspec validate code-only-invites --strict` verde; `e2e:lint`
  OK; reissue spec 2/2. (CONTINUIDADE.md fica para o G4/fechamento.)

## G4. Fechamento

- [ ] G4.1 `EXECUCAO.md`: CONCLUSÃO com o que foi removido, as decisões finais (DA-1/DA-2
  como o dono decidiu) e o estado das suítes
- [ ] G4.2 Resumo pt-BR client-friendly ao dono
