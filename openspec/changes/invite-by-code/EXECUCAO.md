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

## G2 — (pendente)

## G2 — (pendente)

## G3 — (pendente)

## G4 — (pendente)

## G5 — (pendente)
