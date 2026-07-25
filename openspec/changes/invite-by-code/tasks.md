## G0. Reconciliação e esqueleto da change

- [x] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/invite-by-code/spec.md`, `tasks.md`) coerente com o `PLANO.md` e com as
  decisões já fixadas do dono (§F.1 coexiste, §F.2 8 chars/48h/HMAC, §F.3 só o dono,
  §F.4 por-convite)
- [x] G0.2 Escrever `EXECUCAO.md` reconciliando o plano com a REALIDADE do repo (o que
  já existe em `workspace-invitations` e é reusado, o que é novo), com mapa de grupos
  G0..G5, decisões e armadilhas (roteamento `code/*` vs `:token`, overlap de rack-attack,
  pepper fora do banco)
- [x] G0.3 Verificação do grupo: `npx --yes @fission-ai/openspec@1.6.0 validate
  invite-by-code --strict` verde

## G1. Migration aditiva + model

- [x] G1.1 Migration aditiva sobre `invitations`: colunas `code_hash text`,
  `code_expires_at timestamptz NULL`, `code_attempts smallint NOT NULL DEFAULT 0`,
  `code_locked_at timestamptz NULL`; índice único parcial
  `index_invitations_on_code_hash ... WHERE code_hash IS NOT NULL`
- [x] G1.2 Migration: terceiro ramo no `USING` da policy `tenant_isolation` de
  `invitations` (`OR code_hash = NULLIF(current_setting('app.invitation_code_hash',
  true), '')`, `WITH CHECK` inalterado) + função `invitation_by_code(text)`
  `SECURITY DEFINER STABLE` que seta a GUC e seleciona por igualdade de hash; `REVOKE`/
  `GRANT` para `robotrack_app` e `robotrack_migrator`
- [x] G1.3 Model `Invitation`: `SHORT_CODE_ALPHABET` (Crockford Base32),
  `SHORT_CODE_LEN = 8`, `CODE_VALIDITY = 48.hours`; `self.generate_short_code` (cripto,
  sem viés de módulo), `self.code_hash_for(code)` (HMAC com pepper), `normalize_code`
  (upper, tira hífen/espaço, mapeia ambíguos), `code_status`; SEM persistir claro
- [x] G1.4 Spec de banco (SQL cru, sem ActiveRecord): unicidade do `code_hash`,
  `invitation_by_code` acha por hash exato e NÃO por listagem, RLS fail-closed sem GUC,
  convite de outro tenant não vaza; `schema_guard` continua verde
- [x] G1.5 Spec de model: 10.000 códigos distintos e sem I/L/O/U, normalização tolerante
  casa o hash (verificação do grupo G1 — 26/26 verde; suítes de regressão de invitations/
  tenancy/autorização: 276 exemplos, 0 falhas). Retry em `RecordNotUnique` → G2.1/G2.7

## G2. Backend do aceite/preview por código

- [x] G2.1 `CreateService`: gerar o código em claro UMA vez quando o convite deve ter
  código, guardar `code_hash`, setar `code_expires_at`, retornar o claro no payload;
  retry no `RecordNotUnique` do `code_hash` (distinto da colisão pendente-por-e-mail)
- [x] G2.2 `AcceptService#lookup_by_code(code, email)`: normaliza, computa HMAC, ordem
  anti-enumeração (par e-mail → lockout → expiração), `invitation_by_code($hash)`, e
  chama o MESMO `consume`; incremento de `code_attempts` em transação curta na falha do
  par (`Invitation.register_code_failure!`)
- [x] G2.3 `PreviewService#preview_by_code(code, email)` exigindo o par; resposta
  genérica idêntica (corpo/status) para código inexistente e par inválido
- [x] G2.4 Rotas `POST /api/v1/invitations/code/preview` (público, tenant-exempt) e
  `POST /api/v1/invitations/code/accept` (autenticado, tenant-exempt), declaradas ANTES
  de `:token/accept` (namespace `code`); `route_setting :policy, access: :authenticated`
  no accept; corpo `{ code, email }` sem `role`; preview força `status 200`
- [x] G2.5 `Api::Entities::Invitation`: `short_code` (XXXX-XXXX) exposto só na criação;
  `code_status`/`code_expires_at` na listagem; `code_hash` e claro NUNCA
- [x] G2.6 Allowlist: `PUBLIC_ROUTES` (preview), `TENANT_EXEMPT_ROUTES` (ambas),
  `public_routes.yml` (preview com reason); `/code/*` sem `:id` → fora do gerador
  cross-tenant (correto); route-sweep e tenant-sweep verdes
- [x] G2.7 Request specs espelhando o token: aceite ok, e-mail submetido divergente →
  404 genérico, e-mail autenticado divergente → 403, código expirado → 410 (link segue),
  `role` no corpo → 422, duplo-aceite → 409, preview exige par, token segue funcionando
  (verificação do grupo G2 — 12/12 verde; regressão 227/227)

## G3. Endurecimento contra enumeração

- [x] G3.1 `env_schema`: `INVITATION_CODE_PEPPER` registrado (obrigatória em
  produção/staging, guarda de boot herdado) + `RATE_LIMIT_CODE_ACCEPT_GLOBAL`;
  `.env.example` regenerado; pepper lido de credentials/ENV, nunca versionado
- [x] G3.2 `rack_attack`: `code-accept-ip` 5/10min, `code-accept-email` 5/10min,
  `code-accept-global` (300/min, ENV), `code-preview-ip` 10/10min; `throttled_responder`
  loga `code_sha256[0,12]` (do corpo, nunca o claro)
- [x] G3.3 Lockout por convite: após 5 falhas do par, `code_locked_at` setado e `423
  invitation_code_locked`; link segue válido; filtro exato do param `code` no log
- [x] G3.4 Purge/anulação e timing-equality: decididos e registrados no EXECUCAO
  (DE-G3.1/DE-G3.2)
- [x] G3.5 Specs de rate-limit (IP/e-mail/global, log sem claro) e lockout (trava na 6ª,
  link sobrevive, cega não trava, e-mail errado em travado segue genérico); custo de
  brute-force documentado no EXECUCAO (verificação do grupo G3 — 16/16 verde; regressão
  rate-limit token + suíte invitations 80/80)

## G4. Frontend (entrada por código)

- [x] G4.1 `lib/api/endpoints.ts`: `invitationsApi.previewByCode({ code, email })` e
  `acceptByCode({ code, email })`; `short_code?`/`code_status?`/`code_expires_at?` no
  `InvitationDTO`
- [x] G4.2 `lib/auth/invite.ts`: `inviteStore.captureCode/readCode/clearCode` em
  `sessionStorage` via `safeStorage` (par `{code,email}` serializado), sobrevivendo ao
  OAuth; robusto a valor corrompido
- [x] G4.3 `lib/auth/session.ts`: `consumeInviteByCode(code, email)` reusando o mapa de
  erros de `consumeInvite` + `invitation_code_locked` (423), `invitation_code_expired`
  (410) e o genérico de par inválido (`codeInvalidPair`); `handleInviteAfterAuth` checa
  token E código; `performLogout` limpa o par
- [x] G4.4 `AuthPage.tsx`: seção "Tenho um código de convite" (`<details>` fora do form
  de login, sem aninhar), campos E-mail e Código com máscara `XXXX-XXXX` (util
  `lib/auth/code.ts`), normalização tolerante, fundo temático (regra F), alvo ≥ 37px,
  erro por `aria-live`; auted aceita direto, guest guarda o par + marca entrada
- [x] G4.5 `lib/i18n/invitations.ts`: novos literais (`codeSectionTitle`, `codeLabel`,
  `codePlaceholder`, `codeLocked`, `codeExpired`, `codeInvalidPair`, `codeSaved`,
  `inviteCodeReady`, `copyCode`, `codeStatus*`, …); nenhum literal de convite fora daqui
- [x] G4.6 `InviteDialog.tsx`: exibe o código (`XXXX-XXXX`, `font-mono tabular`, "Copiar
  código" com o mesmo fallback do link) ao lado do link, avisando que expira antes.
  `TeamPanel.tsx`: `code_status` (expirado/bloqueado) na linha do convite
- [x] G4.7 Verificação do grupo G4: `vitest` 141/141 (form/normalização/estados/sobrevive
  ao OAuth + contraste + sweeps), `tsc` limpo, `lint` limpo nos arquivos tocados; regra F
  e alvo ≥ 32px conferidos no navegador (dark, campos temáticos, 37–39px, máscara ao vivo
  `il0o4k7p`→`1100-4K7P`, sem erro de console)

## G5. Docs, E2E e fechamento

- [ ] G5.1 Atualizar `CONTINUIDADE.md` (estado, suítes, o que resta), `VALIDACAO_WSL.md`
  (se tocar comando/seletor/topologia), `DESIGN.md` (se tocar token/primitivo/motion)
- [ ] G5.2 E2E do fluxo por código em Chromium (dono cria → copia código → convidado
  digita e-mail+código na entrada → autentica → vira membro); WebKit/CI como handoff
  registrado
- [ ] G5.3 Verificação final: `validate --strict` verde, docs sem afirmação falsa,
  relatório final pt-BR client-friendly com o que ficou pronto, estado das suítes,
  decisões, pendências/handoffs e o que está commitado localmente aguardando push
