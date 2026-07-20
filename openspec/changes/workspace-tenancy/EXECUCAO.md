# EXECUCAO — workspace-tenancy

Mapa de execução das 29 tarefas de `tasks.md`, quebradas em **grupos coerentes**,
um grupo por invocação. Cada grupo é aplicado, verificado e commitado
isoladamente antes do seguinte começar. Mesmo método de
`seal-template-baseline/EXECUCAO.md` (Onda 0, 31/31, 9 commits).

Este arquivo é escrito **antes** de qualquer código, de propósito: se a sessão
cair por limite de uso (já aconteceu na Onda 0), o próximo agente retoma daqui —
o mapa, o estado esperado das suítes por grupo e as decisões de ambiente estão
todos abaixo.

## Ponto de partida

- Branch: `workspace-tenancy`, criada de `seal-template-baseline` (onde o trabalho
  vive; a `main` não tem nada disso). **Sem push** — não há credencial.
- Baseline das suítes (antes de tocar em código, medido em 20/07/2026):
  **backend 67 exemplos / 0 falhas**, **frontend 7 testes / 0 falhas**.
- Pré-requisito da change satisfeito: `X-Skip-Auth` vedado, `spec/factories`
  presente, helper `RequestAuthHelper` de auth de request. Enquanto esse header
  furasse a autenticação nenhum teste negativo de tenancy provaria nada.

## Critério de agrupamento

`tasks.md` codifica coesão por área **e** a ordem de dependência rígida do
`design.md` (§Plano de migração): `workspaces → people → memberships →
RLS/policies → triggers/REVOKE`, e "habilitar RLS antes de existir o helper
`Tenant.with` deixaria a suíte vermelha por motivo certo; por isso o helper e a
allowlist entram na mesma leva". Reagrupar por outro eixo quebraria isso. Os
grupos **adotam as 6 seções de `tasks.md` como fronteira**.

A independência entre grupos é *sequencial*, não *paralela*: cada grupo parte de
uma base sã e entrega outra base sã. G1→G2→…→G6, sem paralelismo.

## Mapa de grupos

| Grupo | Área | Tarefas | Depende de |
|---|---|---|---|
| **G1** | Fundação de esquema e papéis de banco | 1.1, 1.2, 1.3, 1.4 | baseline |
| **G2** | Tabelas de tenancy (workspaces, people, memberships, triggers) | 2.1–2.6 | G1 |
| **G3** | Row Level Security + `Tenant.with` + concern + specs de isolamento | 3.1–3.6 | G2 |
| **G4** | Contexto de tenant nos pontos de entrada (HTTP, Sidekiq, Cable) | 4.1–4.6 | G3 |
| **G5** | Bootstrap e identidade de domínio (`Person`) | 5.1–5.4 | G4 |
| **G6** | Superfície de API e cliente frontend + rebuild limpo | 6.1–6.5 | G5 |

Total: 29 tarefas em 6 grupos.

## Decisões de ambiente (o eixo mais consequente desta change)

O `design.md` exige **isolamento garantido pelo banco**, não pelo Ruby. Para a
suíte *provar* isso localmente, a conexão de runtime (a que os exemplos de rspec
usam) precisa ser um papel **sem** `SUPERUSER` nem `BYPASSRLS`, distinto do papel
de DDL. Sem isso, 1.4, 2.5, 3.4–3.6 e 6.4 seriam teatro. Portanto:

### Dois papéis de banco (G1)

| Papel | Uso | Privilégios |
|---|---|---|
| `robotrack_migrator` | DDL, `db:migrate`, dono das tabelas de tenant | `CREATE` na base; **sem** `SUPERUSER`, **sem** `BYPASSRLS` |
| `robotrack_app` | runtime (Puma, Sidekiq, Cable, **rspec**) | `SELECT/INSERT/UPDATE/DELETE/TRUNCATE`; **sem** `UPDATE(owner_user_id)`; **sem** `SUPERUSER`, **sem** `BYPASSRLS` |

- DDL script idempotente versionado em `backend/db/roles.sql` (só DDL de papel +
  GRANTs; senhas dev-locais, **não** é `.env`, mesmo precedente do `silas777` já
  commitado em `database.yml`). Credenciais reais de staging/prod são
  `delivery-and-observability`.
- `database.yml`: `dev`/`test` conectam como `robotrack_app` por padrão (via
  `DATABASE_URL`, com fallback dev-local). Migrations rodam como
  `robotrack_migrator` via `MIGRATION_DATABASE_URL`.

### Comandos de migração por grupo

O papel `app` não pode rodar DDL (é o ponto: `FORCE RLS` + não-dono). Toda
migration roda como `migrator`, contra dev **e** test, e só então a suíte roda
como `app`:

```bash
export PATH="$HOME/.rbenv/shims:$PATH"
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"

RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate   # gera structure.sql
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate   # sincroniza o test DB
bundle exec rspec                                                          # roda como robotrack_app
```

`maintain_test_schema!` roda como `app`; como o test DB já está migrado pelo
`migrator` e `schema_migrations` bate com os arquivos, ele é no-op (não tenta
DDL). `robotrack_app` recebe `GRANT SELECT` em `schema_migrations`/
`ar_internal_metadata` e `TRUNCATE` nas tabelas para o DatabaseCleaner do
`before(:suite)` funcionar.

### `structure.sql`, não `schema.rb` (1.1 / D-4)

`schema_format = :sql`. Policy, trigger, `REVOKE` de coluna, `CHECK` com
expressão e enum nativo não são representáveis em `schema.rb`; deixá-lo geraria um
esquema regenerado **sem RLS** e o próximo `db:schema:load` nasceria sem
isolamento e verde. `db/schema.rb` é removido; `db/structure.sql` versionado.

### Specs de comportamento de banco rodam com truncation, não transacional

`Tenant.with` usa `set_config(..., true)` (`SET LOCAL`), local à **transação**.
Sob `use_transactional_fixtures`, o `SET LOCAL` de um savepoint aninhado não é
revertido no `RELEASE`, então o cenário "variável é `NULL` após o bloco" (3.x,
4.5) só é fiel fora da transação do RSpec. O `rails_helper` já tem o gancho
`needs_truncation`; ele é estendido para incluir `example.metadata[:tenancy]`.
Specs de isolamento/fail-closed/vazamento levam a tag `:tenancy`.

## Riscos alocados a grupos específicos

- **G2 — `Person` é a decisão mais consequente (D-6).** `user_id` **nullable**,
  `id` estável, mesmo `person_id` preservado quando a pessoa vira usuária
  (`People::ResolveService` preenche `user_id` na linha existente, G5). Índices
  únicos parciais `(workspace_id, email)`, `(workspace_id, user_id)`,
  `(workspace_id, lower(btrim(name)))` e o único `(workspace_id, id)` alvo de FK
  composta. Se sair errado, o defeito de identificação por nome volta e custa
  migração depois. **Nenhuma coluna de domínio guarda nome como chave.**
- **G2 — invariantes no BANCO, não no model.** Dono imutável por
  `REVOKE UPDATE(owner_user_id)` **e** trigger `workspaces_owner_immutable`;
  unicidade de membership por índice único; dono-não-é-membro por trigger
  `memberships_owner_is_not_member`; `"Não Atribuído"` por `CHECK`
  `people_name_not_sentinel`. O model pode ser contornado por um console; a
  constraint não. Spec 2.6 exercita cada uma **por SQL cru**, sem passar por AR.
- **G3 — multi-tenancy real.** Escopo obrigatório por workspace; vazamento entre
  tenants → lista vazia (leitura) ou erro de policy (escrita), nunca dado alheio.
  `FORCE ROW LEVEL SECURITY` (não só `ENABLE`), senão o dono das tabelas ignora a
  policy.
- **G3/G4 — 404 e 403 são duas camadas distintas de anti-enumeração.**
  - **Recurso de outro tenant → 404** (a instrução "vazamento entre tenants =
    404, não 403"). Dentro do contexto de `WS-A`, `Project.find(<id de WS-B>)`
    esbarra na RLS (linha invisível) → `ActiveRecord::RecordNotFound` → `404`.
    Pedir recurso alheio é indistinguível de recurso inexistente. É a spec
    `tenant-isolation` §"find por id de outro tenant não encontra".
  - **Seleção de contexto de workspace → 403** (spec `workspace-core`).
    `ResolveCurrentService` devolve `403 workspace_access_denied` tanto para
    `X-Workspace-Id` de workspace alheio quanto para uuid inexistente — o mesmo
    código nos dois casos, senão a diferença de status vazaria *quais workspaces
    existem*. Header ausente é `400 workspace_context_missing`.

  Não há conflito: a primeira protege a enumeração de **recursos**, a segunda a
  de **workspaces**. As duas são implementadas.
- **G4 — spec de varredura de rotas (4.6) é essencial, não simplificar.** Enumera
  `Api::Root.routes`, subtrai a allowlist de rotas sem tenant, e falha quando um
  endpoint de domínio não passa pela resolução de tenant. Mesmo mecanismo do
  `auth_route_sweep_spec.rb` já existente. Também a guarda de esquema que enumera
  `information_schema.tables` e falha em tabela de domínio sem `workspace_id
  NOT NULL`/`FORCE RLS`/policy.
- **G1 — backup antes de mexer em papel (1.2).** `pg_dump -Fc` do dev DB para
  `backend/tmp/backups/` (gitignored), com comando de restauração documentado,
  antes de qualquer `REVOKE`. Rollback do `REVOKE` = reapontar `DATABASE_URL`.

## Protocolo por grupo

1. Aplicar as tarefas do grupo (migrations como `migrator`, código, specs).
2. `bundle exec rspec` (backend, como `robotrack_app`) e, quando o grupo tocar o
   front, `npx vitest run` (frontend). Comparar com o estado esperado abaixo.
3. Marcar `- [ ]` → `- [x]` em `tasks.md` para as tarefas do grupo.
4. `npx --yes @fission-ai/openspec@1.6.0 validate workspace-tenancy --strict`.
5. Commit local descrevendo o grupo. **Nenhum push.**
6. Conferir que nenhum `.env` real entrou (`backend/.env`, `frontend/.env`
   cobertos por `.gitignore` `**/*.env`); nenhum dump em commit.

## Estado esperado da suíte por grupo

| Após | Backend (rspec, como `robotrack_app`) | Frontend |
|---|---|---|
| Baseline | 67 / 0 | 7 / 0 |
| G1 | 67 (herdados) + guard `db_role_spec` verdes, rodando como `robotrack_app` | inalterado |
| G2 | + specs de esquema SQL (2.6) verdes | inalterado |
| G3 | + specs de RLS/isolamento/fail-closed verdes | inalterado |
| G4 | + specs de contexto/vazamento/route-sweep de tenant verdes | inalterado |
| G5 | + specs de bootstrap/resolução de `Person` verdes | inalterado |
| G6 | + suíte de request negativa da superfície HTTP verde; rebuild limpo verde | + testes de client/endpoints verdes |
| Alvo final | 0 falhas | 0 falhas |

## Comando de CLI de apoio

```bash
npx --yes @fission-ai/openspec@1.6.0 validate workspace-tenancy --strict
npx --yes @fission-ai/openspec@1.6.0 show     workspace-tenancy --json --deltas-only
```

O CLI é a fonte da verdade sobre artefatos e validação; o recorte em G1..G6 é a
camada desta execução, registrada aqui.

## Progresso

- [x] G1 — Fundação de esquema e papéis de banco (1.1–1.4)
- [x] G2 — Tabelas de tenancy (2.1–2.6)
- [x] G3 — Row Level Security + Tenant.with + specs (3.1–3.6)
- [ ] G4 — Contexto nos pontos de entrada (4.1–4.6)
- [ ] G5 — Bootstrap e identidade de domínio (5.1–5.4)
- [ ] G6 — Superfície de API e cliente + rebuild limpo (6.1–6.5)
