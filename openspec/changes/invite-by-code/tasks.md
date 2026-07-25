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

- [ ] G1.1 Migration aditiva sobre `invitations`: colunas `code_hash text`,
  `code_expires_at timestamptz NULL`, `code_attempts smallint NOT NULL DEFAULT 0`,
  `code_locked_at timestamptz NULL`; índice único parcial
  `index_invitations_on_code_hash ... WHERE code_hash IS NOT NULL`
- [ ] G1.2 Migration: terceiro ramo no `USING` da policy `tenant_isolation` de
  `invitations` (`OR code_hash = NULLIF(current_setting('app.invitation_code_hash',
  true), '')`, `WITH CHECK` inalterado) + função `invitation_by_code(text)`
  `SECURITY DEFINER STABLE` que seta a GUC e seleciona por igualdade de hash; `REVOKE`/
  `GRANT` para `robotrack_app` e `robotrack_migrator`
- [ ] G1.3 Model `Invitation`: `SHORT_CODE_ALPHABET` (Crockford Base32),
  `SHORT_CODE_LEN = 8`, `CODE_VALIDITY = 48.hours`; `self.generate_short_code` (cripto,
  sem viés de módulo), `self.code_hash_for(code)` (HMAC com pepper), `normalize_code`
  (upper, tira hífen/espaço, mapeia ambíguos), `code_status`; SEM persistir claro
- [ ] G1.4 Spec de banco (SQL cru, sem ActiveRecord): unicidade do `code_hash`,
  `invitation_by_code` acha por hash exato e NÃO por listagem, RLS fail-closed sem GUC,
  convite de outro tenant não vaza; `schema_guard` continua verde
- [ ] G1.5 Spec de model: 10.000 códigos distintos e sem I/L/O/U, normalização tolerante
  casa o hash, retry em `RecordNotUnique` (verificação do grupo G1 — 0 falhas)

## G2. Backend do aceite/preview por código

- [ ] G2.1 `CreateService`: gerar o código em claro UMA vez quando o convite deve ter
  código, guardar `code_hash`, setar `code_expires_at`, retornar o claro no payload;
  retry no `RecordNotUnique` do `code_hash`
- [ ] G2.2 `AcceptService#lookup_by_code(code, email)`: normaliza, computa HMAC, checa
  lockout/expiração do código, `SELECT * FROM invitation_by_code($hash)`, confere par
  e-mail, e chama o MESMO `consume`; incremento de `code_attempts` em transação curta no
  caminho de falha
- [ ] G2.3 `PreviewService#preview_by_code(code, email)` exigindo o par; resposta
  genérica idêntica (corpo e tempo) para código inexistente e par inválido
- [ ] G2.4 Rotas `POST /api/v1/invitations/code/preview` (público, tenant-exempt) e
  `POST /api/v1/invitations/code/accept` (autenticado, tenant-exempt), declaradas ANTES
  de `:token/accept` (ordem de roteamento); `route_setting :policy, access:
  :authenticated` no accept; corpo `{ code, email }` sem `role`
- [ ] G2.5 `Api::Entities::Invitation`: `short_code` exposto só na criação;
  `code_status`/`code_expires_at` na listagem; `code_hash` e claro NUNCA
- [ ] G2.6 Allowlist: `PUBLIC_ROUTES` (preview), `TENANT_EXEMPT_ROUTES` (ambas),
  `public_routes.yml` (preview com reason); confirmar que `/code/*` não é elegível ao
  gerador cross-tenant (sem `:id`) e que o route-sweep aceita as duas
- [ ] G2.7 Request specs espelhando o token: aceite ok, corrida (200/409), e-mail
  divergente, código expirado, `role` no corpo → 422, preview exige par, token segue
  funcionando (verificação do grupo G2 — 0 falhas)

## G3. Endurecimento contra enumeração

- [ ] G3.1 `env_schema`: `INVITATION_CODE_PEPPER` registrado (obrigatória em
  produção/staging, guarda de boot), regenerar `.env.example`; pepper lido de
  credentials/ENV, nunca versionado
- [ ] G3.2 `rack_attack`: `code-accept-ip` 5/10min, `code-accept-email` 5/10min,
  `code-preview-ip` 10/10min e teto GLOBAL de falhas de código; `throttled_responder`
  loga `code_sha256[0,12]`
- [ ] G3.3 Lockout por convite: após 5 falhas do par, `code_locked_at` setado e `423
  invitation_code_locked`; link segue válido; scrubber cobre o código no log
- [ ] G3.4 Purge/anulação do código quando só o CÓDIGO expira (48h < 7d) mas o link
  ainda vale — decidir e registrar no EXECUCAO; timing-equality entre código
  inexistente e existente
- [ ] G3.5 Specs de rate-limit (IP/e-mail/global), lockout (trava na 6ª, link sobrevive,
  cega não trava), log-scrubber (nunca claro); custo de brute-force documentado no
  EXECUCAO (verificação do grupo G3 — 0 falhas)

## G4. Frontend (entrada por código)

- [ ] G4.1 `lib/api/endpoints.ts`: `invitationsApi.previewByCode({ code, email })` e
  `acceptByCode({ code, email })`; `short_code?` no `InvitationDTO`
- [ ] G4.2 `lib/auth/invite.ts`: `inviteStore.captureCode/readCode/clearCode` em
  `sessionStorage` via `safeStorage`, sobrevivendo ao OAuth
- [ ] G4.3 `lib/auth/session.ts`: `consumeInviteByCode(code, email)` reusando o mapa de
  erros de `consumeInvite` + `invitation_code_locked` (423) e o genérico de par inválido;
  `handleInviteAfterAuth` checa token E código
- [ ] G4.4 `AuthPage.tsx`: seção "Tenho um código de convite" (collapsible), campos
  E-mail e Código com máscara `XXXX-XXXX`, normalização tolerante, fundo temático
  (regra F), alvo ≥ 32px, erros por `aria-live` no campo certo
- [ ] G4.5 `lib/i18n/invitations.ts`: novos literais (`codeSectionTitle`, `codeLabel`,
  `codePlaceholder`, `codeLocked`, `codeInvalidPair`, `codeAccepted`, …); nenhum literal
  de convite fora daqui
- [ ] G4.6 `InviteDialog.tsx`: exibir o código (`XXXX-XXXX`, `tabular`, "Copiar código"
  com o mesmo fallback do "Copiar link") ao lado do link; deixar claro que o código
  expira antes do link. `TeamPanel.tsx`: `code_status` na linha do convite
- [ ] G4.7 Verificação do grupo G4: `vitest` (form, normalização, estados de erro,
  sobrevive ao OAuth), regra F (fundo temático), alvo ≥ 32px, `tsc`/`lint`/sweeps —
  0 falhas

## G5. Docs, E2E e fechamento

- [ ] G5.1 Atualizar `CONTINUIDADE.md` (estado, suítes, o que resta), `VALIDACAO_WSL.md`
  (se tocar comando/seletor/topologia), `DESIGN.md` (se tocar token/primitivo/motion)
- [ ] G5.2 E2E do fluxo por código em Chromium (dono cria → copia código → convidado
  digita e-mail+código na entrada → autentica → vira membro); WebKit/CI como handoff
  registrado
- [ ] G5.3 Verificação final: `validate --strict` verde, docs sem afirmação falsa,
  relatório final pt-BR client-friendly com o que ficou pronto, estado das suítes,
  decisões, pendências/handoffs e o que está commitado localmente aguardando push
