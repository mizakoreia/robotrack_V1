#!/usr/bin/env bash
set -euo pipefail

# Release de STAGING = release de produção + a camada de REVOKE append-only que, em
# produção real, é reaplicada pós-migrate (db/roles.sql). Roda no serviço `release`
# do compose de staging, com DATABASE_URL apontando para o migrator (dono das
# tabelas). Chamado por `bash /staging/release.sh` (sem exigir bit de exec no mount).
#
#   1. bin/release  → guarda de backup + db:migrate, como o migrator.
#   2. REVOKE append-only, como o migrator, para o app perder UPDATE/DELETE sobre
#      audit_logs/task_advances/... — senão o guard de imutabilidade aborta web e
#      worker (BUG 10). psql vem no backend-base (postgresql-client).

echo "[release] rodando bin/release (migrate como migrator)…"
bin/release

echo "[release] aplicando REVOKE append-only de staging (como migrator, dono)…"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f /staging/append_only_revokes.sql

echo "[release] papéis de staging reconciliados — app sem UPDATE em tabelas append-only"
