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

## G1 — (pendente)

## G2 — (pendente)

## G3 — (pendente)

## G4 — (pendente)

## G5 — (pendente)
