# Provisionamento de banco — workspace-tenancy

Papéis, backup e o fluxo de migração com dois papéis. Credenciais **reais** de
staging/prod são `delivery-and-observability`; aqui só o setup dev-local.

## Papéis (design D-11 / tenant-isolation §"Papel de banco")

| Papel | Uso | Privilégios |
|---|---|---|
| `robotrack_migrator` | DDL, `db:migrate`, dono dos bancos e das tabelas de tenant | `CREATEDB`; **sem** `SUPERUSER`, **sem** `BYPASSRLS` |
| `robotrack_app` | runtime (Puma, Sidekiq, Cable, rspec) | `SELECT/INSERT/UPDATE/DELETE/TRUNCATE`; **sem** `UPDATE(owner_user_id)`; **sem** `SUPERUSER`, **sem** `BYPASSRLS` |

Setup (idempotente; superusuário), uma vez por banco:

```bash
psql -U robotrack_user -d robotrack_dev  -f db/roles.sql
psql -U robotrack_user -d robotrack_test -f db/roles.sql
```

`db/roles.sql` cria os papéis, dá `CREATEDB` ao migrator, torna-o dono dos
bancos, instala `pgcrypto`/`citext`, concede DML ao app e transfere as tabelas
serial não-tenant (ex.: `jwt_denylist`) ao app — necessário porque a truncation
de teste emite `TRUNCATE ... RESTART IDENTITY`, que exige ownership da sequence.

## Fluxo de migração (dois papéis)

A app conecta como `robotrack_app`, que **não** roda DDL (é o ponto: `FORCE RLS`
+ não-dono). Migrations rodam como `robotrack_migrator`:

```bash
export PATH="$HOME/.rbenv/shims:$PATH"
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"

RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate  # gera db/structure.sql
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate  # sincroniza o test DB
bundle exec rspec                                                         # roda como robotrack_app
```

Depois de recriar um banco do zero (`db:drop/create/schema:load` como migrator,
tarefa 6.5), **reaplique `db/roles.sql`** — a recriação apaga grants e ownership
de tabela.

## Backup e restauração (tarefa 1.2 — obrigatório antes de mudar papel/REVOKE)

```bash
# Backup lógico
pg_dump -Fc "$MIG_DEV" -f tmp/backups/robotrack_dev_$(date +%Y%m%d_%H%M%S).dump

# Restauração num banco descartável para conferir o dump
createdb -U robotrack_user robotrack_restore_check
pg_restore --no-owner --role=robotrack_migrator \
  -d "postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_restore_check" \
  tmp/backups/<arquivo>.dump
```

`tmp/backups/` é gitignored (`.gitignore` → `backend/tmp/`) — nenhum dump entra
em commit. Rollback do `REVOKE`/troca de papel: reapontar `DATABASE_URL` para o
papel anterior; o `REVOKE` sozinho não perde dado.
