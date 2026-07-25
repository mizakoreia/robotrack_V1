# EXECUCAO — invite-by-code

Registro de execução por grupo: reconciliação com a realidade do repo, decisões
tomadas, armadilhas e provas. Método da casa (CLAUDE.md): uma change por vez, grupo a
grupo, specs dirigidos 0 falhas, doc atualizada no mesmo passo, um commit `G<n>:` por
grupo.

> **Restrição de git vigente (instrução do dono):** NÃO fazer push para `origin` e NÃO
> fazer `git merge --ff-only main`. O trabalho vive no branch local `feat/invite-by-code`
> com commits `G<n>:` LOCAIS; o dono acumula antes de subir. Qualquer necessidade de
> subir é PERGUNTA, não ação.

---

## G0 — Reconciliação (este documento) + esqueleto OpenSpec

### O que já existe e será REUSADO (a base madura)

Levantado lendo o código real (não só o PLANO): `workspace-invitations` está completa e
publicada. Este change CONSOME, sem modificar:

| Peça (caminho real) | Papel | Como o código reusa |
|---|---|---|
| `db/migrate/20260721120003…rls.rb` — policy `tenant_isolation` + `invitation_by_token` | Lê a linha por token exato sem workspace, sem BYPASSRLS | O código ADICIONA um 3º ramo no `USING` e uma função `invitation_by_code` gêmea |
| `app/models/invitation.rb` — `generate_token`, `assign_token on: :create`, `status`, `email_masked` | Model do convite | Ganha `generate_short_code`, `code_hash_for`, `normalize_code`, `assign_short_code`, `code_status` ao lado |
| `app/services/invitations/accept_service.rb` — `consume`, `validate!` (6 condições), `resolve_person`, `FOR UPDATE` | Consumo atômico (invariante 6) | O código adiciona só `lookup_by_code`; chama o MESMO `consume`. Zero duplicação |
| `app/services/invitations/create_service.rb` | Criação restrita ao dono | Ganha a geração do código + retorno do claro uma vez |
| `app/services/invitations/preview_service.rb` — `lookup` via `invitation_by_token` | Preview público por token | Ganha `preview_by_code(code, email)` exigindo o par |
| `app/controllers/api/v1/invitation_tokens.rb` — `before { header 'Referrer-Policy','no-referrer' }`, `GET :token`, `POST :token/accept` | Superfície pública/isenta de tenant | As rotas `code/*` entram AQUI, declaradas ANTES de `:token/accept` |
| `app/controllers/api/entities/invitation.rb` — expõe `invite_url`, nunca o token cru | Serialização | Ganha `short_code` só na criação, `code_status`/`code_expires_at` na listagem |
| `app/controllers/api/root.rb` — `PUBLIC_ROUTES`, `TENANT_EXEMPT_ROUTES` (cientes de método) | Allowlist | Ganha entradas para `POST /code/preview` (pública) e `POST /code/accept` (isenta) |
| `config/initializers/rack_attack.rb` — accept-ip/session, preview-ip, `throttled_responder` com `token_sha256` | Rate-limit + log | Ganha `code-accept-ip`/`code-accept-email`/`code-preview-ip`/global + `code_sha256` |
| `config/initializers/invitation_log_scrubber.rb` — troca `rt_inv_...` por hash | Log sem token | Ganha padrão do código (evitar claro no log) |
| `config/env_schema.rb` — registro único de ENV + guarda de boot | Config auditável | Ganha `INVITATION_CODE_PEPPER` |
| `spec/authorization/route_sweep_spec.rb`, `cross_tenant_spec.rb`, `tenancy/tenant_route_sweep_spec.rb`, `config/authorization/public_routes.yml` | Varreduras que só crescem | Rotas `/code/*` entram nas allowlists; `/code/*` NÃO é elegível ao cross-tenant (sem `:id`) — correto, o lookup é por hash sob RLS |
| `frontend/src/features/auth/{InviteRoute,AuthPage}.tsx`, `lib/auth/{session,invite}.ts`, `lib/api/endpoints.ts`, `lib/i18n/invitations.ts`, `features/team/{TeamPanel,InviteDialog}.tsx` | Fluxo do convidado por link | Ganham os análogos por código, reusando o mapa de erros e o `sessionStorage` |

### Divergências entre o PLANO e a realidade (reconciliadas)

1. **Caminho dos arquivos.** O PLANO cita `api/v1/invitations.rb` etc. na raiz de `app`;
   a realidade é `backend/app/controllers/api/...`. Sem impacto de design, só de path.
2. **Rota de aceite por token colide com `code/accept`.** `POST /invitations/:token/
   accept` casaria `code/accept` (token = "code"). **Decisão:** declarar as rotas
   `code/*` ANTES de `:token/accept` na mesma classe Grape (ordem de roteamento resolve),
   espelhando o cuidado de `session/?$` vs `session/renew` em `identity-and-auth`.
3. **Overlap de rack-attack.** `ACCEPT_PATH = %r{/invitations/[^/]+/accept}` também casa
   `/invitations/code/accept`; logo os throttles do token (accept-ip 10/10) TAMBÉM
   incidem sobre o accept por código. **Decisão:** aceitar o overlap (o teto do código,
   5/10, é mais apertado e morde primeiro); o `token_sha256` logado nesse caso é
   `sha256("code")`, inócuo. Registrado para não surpreender.
4. **`/code/*` sem `:id` → fora do gerador cross-tenant.** O `cross_tenant_spec` só é
   elegível para paths com `/:(\w+_)?id`. As rotas por código não endereçam recurso por
   id (o lookup é por hash sob RLS), então não entram — e isso é correto, não uma
   omissão. A prova cross-tenant do código é a spec de RLS do G1 (convite de outro tenant
   não vaza por código).
5. **Pepper.** O PLANO deixou em aberto "app computa o HMAC ou a função". **Decisão
   (D2 do design):** o APP computa; a função recebe já o hash. Mantém o pepper fora do
   banco (nenhum `pg_stat_statements`/log de query o exporia).
6. **Migration numbering.** Última migration do repo: `20260724110002`. A nova nasce como
   `20260724120001_add_short_code_to_invitations.rb` (posterior, mesma data 2026-07-24).

### Decisões-âncora (detalhadas em design.md D1..D9)

- **D1** coluna na mesma linha, não tabela nova.
- **D2** `code_hash` = HMAC com pepper (app computa); nunca claro no banco.
- **D3** ramo RLS + `invitation_by_code`, sem BYPASSRLS.
- **D4** aceite reusa `consume`; só o lookup é novo.
- **D5** preview exige o par (código+e-mail); anti-colheita de phishing.
- **D6** rotas `/code/*` POST, antes do `:token`.
- **D7** 48h + lockout por convite (limite: só morde código existente).
- **D8** rate-limit IP/e-mail/global; overlap de rack-attack registrado.
- **D9** claro só na criação (`short_code` na entity uma vez).

### Não-objetivos reafirmados

Código de workspace reutilizável (§F.4 descartado), mudança na matriz de autorização
(§F.3 — só o dono convida), envio de e-mail/SMS, alteração do fluxo do link, convite a
`owner`. Ver `proposal.md` §Não-objetivos.

### Prova do G0

- `npx --yes @fission-ai/openspec@1.6.0 validate invite-by-code --strict` →
  **`Change 'invite-by-code' is valid`** ✓ (2026-07-24).

### Commit local do G0

- `G0: materializa change invite-by-code (proposal/design/specs/tasks) + EXECUCAO`
  (LOCAL, sem push).

---

## G1 — Migration aditiva + model

### Entregue

- Migration `db/migrate/20260724120001_add_short_code_to_invitations.rb`: colunas
  `code_hash`/`code_expires_at`/`code_attempts`/`code_locked_at`, índice único parcial
  `index_invitations_on_code_hash WHERE code_hash IS NOT NULL`, terceiro ramo no `USING`
  da `tenant_isolation` (via `ALTER POLICY`, reversível no `down`), função
  `invitation_by_code(text)` `SECURITY DEFINER STABLE` (recebe o HASH; pepper fora do
  banco), `REVOKE`/`GRANT` a `robotrack_app` e `robotrack_migrator`.
- Model `Invitation`: `SHORT_CODE_ALPHABET` (Crockford, sem I/L/O/U), `SHORT_CODE_LEN=8`,
  `CODE_VALIDITY=48.hours`, `attr_accessor :short_code` (claro transiente),
  `generate_short_code` (sem viés de módulo — alfabeto de 32 = potência de 2),
  `code_hash_for` (HMAC-SHA256 com pepper, normaliza antes), `normalize_code` (upper,
  tira hífen/espaço, I/L→1, O→0), `code_pepper` (credentials→ENV→default dev/test),
  `code_status`/`code_expired?`/`code_locked?`/`has_code?`, callback
  `assign_short_code on: :create`.

### Decisões de execução

- **DE-G1.1 — todo convite nasce com código.** Resolve a subquestão menor de §F.1
  (código sempre gerado, sem toggle na UI): o código COEXISTE com o link em todo
  convite. Mais simples de operar e de explicar ao dono; o link segue sendo o caminho
  forte, o código a conveniência.
- **DE-G1.2 — `ALTER POLICY` em vez de `DROP/CREATE`.** O Postgres suporta trocar só o
  `USING` da policy existente; mais limpo e reversível que recriar a policy inteira.
- **DE-G1.3 — pepper com default só em dev/test no G1.** A função `code_hash_for`
  precisa ser exercível pela suíte agora; o registro no `env_schema` e a guarda de boot
  em produção/staging são do G3 (endurecimento). Fora de dev/test, `code_pepper` já
  levanta se ausente.
- **DE-G1.4 — dump com `PGTZ=UTC`.** O `structure.sql` regenerado sob o fuso local (-03)
  reescreveria as fronteiras de partição de `audit_logs` (ruído alheio a esta change).
  Migrar com `PGTZ=UTC` mantém o dump em UTC e o diff limpo (só as adições do código).

### Prova do G1

- `bundle exec rspec spec/invitations/short_code_generation_spec.rb spec/invitations/
  code_schema_spec.rb` → **26 exemplos, 0 falhas**.
- Regressão: `spec/invitations spec/tenancy/schema_guard_spec.rb
  spec/tenancy/schema_constraints_spec.rb spec/authorization/cross_tenant_spec.rb
  spec/authorization/route_sweep_spec.rb spec/authorization/invariants` →
  **276 exemplos, 0 falhas, 2 pending** (os 2 pending são stubs pré-existentes de
  invariantes 4/8, alheios a esta change).
- `schema_guard` verde: o índice `code_hash` não começa por `workspace_id`, mas a guarda
  exige apenas ≥1 índice começando por `workspace_id` (já existe
  `index_invitations_on_workspace_id_and_created_at`) — mesmo caso do índice de `token`.

### Commit local do G1

- `G1: migration aditiva (code_hash/RLS/invitation_by_code) + model do código`
  (LOCAL, sem push).

## G2 — Backend do aceite/preview por código

### Entregue

- `AcceptService`: aceita `code`/`email` além de `token`; `lookup_by_code` com a ORDEM
  anti-enumeração (par e-mail → lockout → expiração), chamando o MESMO `consume`;
  `reject_unexpected_parameters!` agora é CIENTE DE MODO (token só admite `token`;
  código só `code`/`email` — `role` no corpo de qualquer um é 422).
- `PreviewService`: `preview_by_code` exigindo o par; genérico (404) idêntico para
  código inexistente e par inválido.
- `Invitation` (model): `row_by_code`, `code_row_expired?`, `register_code_failure!`
  (transação curta, `update_columns`, trava na Nª falha), `CODE_MAX_ATTEMPTS = 5`.
- `CreateService`: retry no `RecordNotUnique` do `code_hash` (distinto da colisão
  pendente-por-e-mail, que sobe como 409); o `short_code` transiente vai no payload.
- Entity `Invitation`: `short_code` (XXXX-XXXX) só na criação; `code_status`/
  `code_expires_at` na listagem; `code_hash`/claro nunca.
- Rotas em `InvitationTokens` (namespace `code`, ANTES de `:token`): `POST /code/preview`
  (público, `status 200`) e `POST /code/accept` (`access: :authenticated`).
- Allowlists: `PUBLIC_ROUTES` (+preview), `TENANT_EXEMPT_ROUTES` (+preview/+accept),
  `public_routes.yml` (+preview com reason).

### Decisões / armadilhas confirmadas

- **DE-G2.1 — preview é POST mas responde 200.** O Grape assume 201 para POST; forcei
  `status 200` (é uma LEITURA; POST só por causa do e-mail no corpo).
- **DE-G2.2 — ordem anti-enumeração (§B.3).** O estado discriminado do código
  (423 travado / 410 expirado / 409 usado) só é revelado ao PAR que já casou
  e-mail+código. Código cego ou e-mail errado → 404 genérico + contabiliza a falha.
- **DE-G2.3 — duas checagens de e-mail coexistem.** O e-mail SUBMETIDO no par (eixo do
  lockout, em `lookup_by_code`) é distinto da condição 5 do `validate!`, que compara com
  o e-mail AUTENTICADO dentro da transação. Ana, autenticada, conhecendo o código E o
  e-mail de João, passa o par mas leva 403 `invitation_email_mismatch` no consume.
- **DE-G2.4 — colisão de roteamento resolvida.** `namespace :code` declarado ANTES de
  `:token/accept` faz o Grape casar `/code/accept` como rota literal, não como
  `token="code"`. Confirmado pelos specs (aceite por código responde, token intacto).
- **Confirmado:** `/code/*` sem `:id` → fora do gerador cross-tenant (correto; a prova
  cross-tenant do código é o `code_schema_spec` do G1). Lockout (mecanismo) já vive
  aqui; rate-limit/env/specs de lockout são G3.
- **Corrida:** não dupliquei o teste com threads — o caminho por código chama o MESMO
  `consume` já provado por `concurrent_accept_spec`. O `code_flow_spec` prova o one-shot
  sequencial (segundo aceite → 409).

### Prova do G2

- `spec/requests/invitations/code_flow_spec.rb` → **12 exemplos, 0 falhas**.
- Regressão: `accept_spec`, `create_spec`, `end_to_end_spec`, `team_panel_spec`,
  `route_sweep_spec`, `tenant_route_sweep_spec`, `cross_tenant_spec` → **227/227 verde**
  (a única falha da 1ª rodada foi o 201→200 do preview, já corrigida).

### Commit local do G2

- `G2: aceite/preview por codigo (services reusam consume, rotas /code/*, entity)`
  (LOCAL, sem push).

## G3 — Endurecimento contra enumeração

### Entregue

- `env_schema`: `INVITATION_CODE_PEPPER` (obrigatória em produção/staging; o guarda de
  boot de `delivery-and-observability` já cobra o que está no schema) e
  `RATE_LIMIT_CODE_ACCEPT_GLOBAL` (opcional, default 300). `.env.example` regenerado
  (25 variáveis) — o spec de sincronia do schema segue verde.
- `rack_attack`: `invitations/code-accept-ip` 5/10min, `invitations/code-accept-email`
  5/10min (e-mail do corpo), `invitations/code-accept-global` (300/min, ENV,
  discriminador constante) e `invitations/code-preview-ip` 10/10min. O
  `throttled_responder` loga `code_sha256[0,12]` do código NORMALIZADO do corpo nos
  caminhos `/code/*` (e `token_sha256` fora deles) — nunca o claro.
- `filter_parameter_logging`: lambda de filtro EXATO do param `code` (não substring,
  para não redigir `country_code`/`zip_code`).
- Lockout por convite: mecânica de G2 (`register_code_failure!` + `CODE_MAX_ATTEMPTS`)
  agora coberta por spec.

### Decisões de execução

- **DE-G3.1 — não anular o código quando só ele expira.** Quando o CÓDIGO vence (48h) mas
  o LINK ainda vale (7d), NÃO se anula `code_hash`/`code_expires_at`. Motivos: (a) um
  código expirado já é recusado no `lookup_by_code` (`410` uma vez que o par casa) e
  continua recusado; (b) o slot no índice único de `code_hash` é aleatório e não escasso;
  (c) o `purge_expired_invitations()` existente já remove a LINHA inteira quando o convite
  está pendente e expirado há >30d (cobre o link e, com ele, o código). Anular ativamente
  seria trabalho sem ganho de segurança. Registrado para o caso de o dono querer, no
  futuro, "aposentar só o código" — seria um job novo, decisão própria.
- **DE-G3.2 — timing-equality: igualdade de CORPO/STATUS garantida; timing perfeito não.**
  Código inexistente e par inválido devolvem o MESMO corpo e status (`404`
  `invitation_not_found`) — sem canal lateral de CONTEÚDO. Há uma assimetria de TEMPO: o
  par inválido faz um `UPDATE` curto (`register_code_failure!`) que o código inexistente
  não faz, então a resposta ao par inválido é marginalmente mais lenta. Tornar isso
  perfeitamente constante (ex.: escrita-fantasma no caminho inexistente) foi avaliado e
  DESCARTADO: acopla o caminho a um custo artificial e a defesa real contra enumeração é a
  soma rate-limit (IP/e-mail/global) + expiração 48h + exigência do e-mail, não a
  indistinguibilidade temporal de milissegundos. Registrado como limite conhecido; se um
  dia virar requisito, é handoff próprio.
- **DE-G3.3 — teto global com chave constante.** `code-accept-global` conta TODOS os
  aceites por código (não só falhas — o rack-attack corre antes do endpoint e não sabe o
  desfecho). É um proxy aceitável: aceite legítimo é raro (um por convidado); 300/min
  deixa passar onboarding simultâneo de um time e ainda corta brute-force distribuído. O
  overlap com o `accept-ip` do token (a regex `ACCEPT_PATH` casa `/code/accept`) é
  benigno — o teto do código (5) morde antes do do token (10).

### Custo de brute-force (documentado)

Espaço do código: 32⁸ = 2⁴⁰ ≈ 1,1 × 10¹². Por IP: 5 aceites/10min ⇒ ~720/dia/IP. Por
e-mail-alvo: 5/10min (o eixo que o IP não cobre). Global: 300/min ⇒ ~432 mil/dia no
sistema inteiro, ainda que o atacante rode IPs infinitos. Para acertar UM código válido
específico (janela de 48h) enumerando às cegas, mesmo saturando o teto global, a fração
do espaço coberta em 48h é ~864 mil / 1,1×10¹² ≈ **8×10⁻⁷** — e cada acerto ainda exige
controlar a conta de e-mail do convidado (condição 5). Somada ao lockout por convite (5
falhas do par travam o código), a adivinhação online é proibitiva.

### Prova do G3

- `spec/invitations/code_lockout_spec.rb` + `spec/requests/invitations/code_rate_limit_spec.rb`
  + `spec/config/env_schema_spec.rb` → **16 exemplos, 0 falhas**.
- Regressão: `spec/requests/invitations/rate_limit_spec.rb` (token) + `spec/invitations`
  → **80 exemplos, 0 falhas** (o `throttled_responder` novo não regrediu o log do token).

### Commit local do G3

- `G3: endurecimento (rate-limit IP/email/global, lockout, pepper, log sem claro)`
  (LOCAL, sem push).

## G4 — Frontend (entrada por código)

### Entregue

- `lib/api/endpoints.ts`: `previewByCode`/`acceptByCode` (preview público via
  `postPublic`, aceite autenticado via `post`); `InvitationDTO` ganha `short_code?`/
  `code_status?`/`code_expires_at?`.
- `lib/auth/invite.ts`: `captureCode`/`readCode`/`clearCode` (par `{code,email}` em
  JSON, chave própria `robotrack.invite_code`; robusto a valor corrompido).
- `lib/auth/code.ts` (novo): `normalizeInviteCode` (Crockford, I/L→1, O→0),
  `formatInviteCode` (máscara `XXXX-XXXX`), `isCompleteInviteCode`.
- `lib/auth/session.ts`: `consumeInviteByCode` reusando o mapa de erros +
  `invitation_code_locked`/`invitation_code_expired`/`codeInvalidPair`;
  `handleInviteAfterAuth` cobre token E código; `performLogout` limpa o par.
- `features/auth/AuthPage.tsx`: seção `<details>` "Tenho um código de convite" (fora do
  form de login, sem aninhar forms), campos temáticos, máscara ao vivo, aria-live.
- `features/team/InviteDialog.tsx`: exibe o código (mono/tabular, "Copiar código" com
  fallback) ao lado do link. `features/team/TeamPanel.tsx`: `code_status` na linha.
- `lib/i18n/invitations.ts`: literais de código (o CI proíbe strings de convite fora
  daqui — `convention-sweep` verde).

### Decisões de execução

- **DE-G4.1 — a seção de código fica FORA do `<form>` de login.** Forms aninhados são
  HTML inválido; o `<details>` com seu próprio form é irmão do form de login dentro do
  container `max-w-sm`. Resolve o aninhamento sem perder o layout de coluna única.
- **DE-G4.2 — todo convite tem código; a UI reflete isso.** Como o backend sempre gera
  código (DE-G1.1), o `InviteDialog` sempre mostra o bloco de código; não há toggle
  "gerar código".
- **DE-G4.3 — normalização no cliente é ergonomia, não segurança.** `code.ts` espelha o
  backend, mas a igualdade de hash é do servidor (que normaliza de novo). O cliente só
  poupa o usuário de errar por maiúscula/hífen/ambíguo.
- **DE-G4.4 — dois eixos de e-mail na tela.** A seção tem campo de e-mail PRÓPRIO (o do
  convite), pré-preenchido do login quando vazio — o e-mail do convite pode diferir do
  que a pessoa digita no login. É o mesmo par que o backend exige.

### Prova do G4

- Verificação no navegador (dev server no caminho correto): `/entrar` renderiza no tema
  escuro; a seção expande com campos de FUNDO TEMÁTICO (regra F — nada de branco no
  escuro); alvos de toque 37–39px (≥32px, luva); máscara ao vivo `il0o4k7p` → `1100-4K7P`
  (normalização tolerante); sem erro de console.
- `vitest run` (tests/ + auth + team + api): **141 exemplos, 0 falhas** (inclui
  `contrast`, `no-emoji`, `no-prefers-color-scheme`, `query-convention`, `stacking`,
  `token-source`; e os novos `code`/`inviteCode`/`AuthPageCode`).
- `tsc --noEmit` limpo; `eslint` limpo nos arquivos tocados (os 4 erros de `eslint` são
  em `e2e/` — pré-existentes, não tocados por esta change; handoff registrado no G5).

### Commit local do G4

- `G4: entrada por codigo na AuthPage + codigo no InviteDialog/TeamPanel`
  (LOCAL, sem push).

## G5 — Docs, E2E e fechamento

### Entregue

- `CONTINUIDADE.md`: seção nova "Change NOVA: `invite-by-code`" — estado, entregas por
  grupo, suítes, e o AVISO explícito de que esta change NÃO seguiu o "ff a `main` +
  push" por instrução do dono (vive local em `feat/invite-by-code`).
- `VALIDACAO_WSL.md`: §6b — handoff da execução do E2E por código em Chromium (mesmo
  setup/semente `[convite]` do §6).
- `frontend/e2e/tests/invite-code.spec.ts`: fluxo por código ponta a ponta, locators
  ancorados por diálogo/região + `{ exact: true }`; **aprovado no `e2e:lint`**.

### Decisões de execução

- **DE-G5.1 — `DESIGN.md` não muda.** A change reusa tokens (`bg-bg-main`/`text-text-
  main`/`border-input`/`bg-bg-panel`) e o primitivo nativo `<details>`; nenhum token,
  primitivo, motion ou ban novo. Pela tabela do CLAUDE.md, `DESIGN.md` só é atualizado
  quando o sistema visual muda — não é o caso.
- **DE-G5.2 — E2E-green é HANDOFF, não [x] de verde.** O CLAUDE.md proíbe `[x]` sem
  prova verde; este container não tem Playwright/Docker (o próprio `VALIDACAO_WSL.md`
  registra isso para TODO E2E da casa). Marca-se o spec como ESCRITO + `e2e:lint` verde,
  e a execução em Chromium como handoff — coerente com como a casa trata E2E.

### Prova do G5

- `e2e:lint` → **OK, 4 spec(s)** (inclui `invite-code.spec.ts`).
- `validate --strict` → verde.
- Docs relidos: sem afirmação falsa (o git-local é dito explicitamente; o E2E é dito
  handoff, não verde).

### Commit local do G5

- `G5: docs (CONTINUIDADE/VALIDACAO) + E2E por codigo (lint verde) + fechamento`
  (LOCAL, sem push).

---

## Estado final da change (aguardando decisão do dono sobre push)

- **Grupos G0..G5 completos**, todos com specs dirigidos verdes e commits `G<n>:`
  **LOCAIS** em `feat/invite-by-code`. NADA empurrado; NADA mergeado a `main`.
- `validate --strict` verde em cada grupo.
- **Handoff aberto:** rodar `invite-code.spec.ts` em Chromium (e WebKit/CI) na WSL —
  §6b do `VALIDACAO_WSL.md`.
- **Não-objetivos preservados:** sem código de workspace reutilizável (§F.4), sem mudar
  a matriz de autorização (§F.3 — só o dono convida), sem e-mail/SMS, link intocado.
