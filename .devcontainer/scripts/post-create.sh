#!/usr/bin/env bash
# Provisionamento ÚNICO do Codespace (roda uma vez, ao criar). Idempotente: pode
# ser reexecutado sem estragar nada. Segue backend/db/PROVISIONING.md — os DOIS
# papéis (migrator/app), extensões e grants vêm de backend/db/roles.sql, e o
# schema é aplicado via `db:migrate` COMO MIGRATOR (não `schema:load`: o
# structure.sql tem `COMMENT ON EXTENSION`, que exigiria posse da extensão — o
# db:migrate roda os enable_extension idempotentes sem tocar nesse comando).
set -euo pipefail

cd "$(dirname "$0")/../.."   # raiz do repositório
ROOT="$(pwd)"
echo "▸ Raiz do projeto: $ROOT"

echo "▸ Instalando dependências de sistema (cliente psql + libpq para a gem pg)…"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  postgresql-client libpq-dev
sudo rm -rf /var/lib/apt/lists/*

echo "▸ Pré-instalando o Claude Code CLI (login é interativo, feito 1x por você)…"
npm install -g @anthropic-ai/claude-code \
  || echo "⚠ Não instalou o Claude Code agora. Rode manualmente: npm install -g @anthropic-ai/claude-code"

echo "▸ Instalando gems do backend (Ruby $(ruby -v 2>/dev/null))…"
( cd backend && gem install bundler --no-document >/dev/null 2>&1 || true && bundle install )

echo "▸ Instalando pacotes do frontend…"
( cd frontend && npm ci )

echo "▸ Aguardando o Postgres ficar pronto…"
export PGHOST="${PGHOST:-postgres}" PGPORT="${PGPORT:-5432}" \
       PGUSER="${PGUSER:-postgres}" PGPASSWORD="${PGPASSWORD:-postgres_bootstrap_pw}"
for _ in $(seq 1 60); do pg_isready -q && break; sleep 1; done
pg_isready || { echo "✗ Postgres não respondeu."; exit 1; }

echo "▸ Criando bancos robotrack_dev / robotrack_test (idempotente)…"
psql -v ON_ERROR_STOP=1 -d postgres <<'SQL'
SELECT 'CREATE DATABASE robotrack_dev'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'robotrack_dev')\gexec
SELECT 'CREATE DATABASE robotrack_test'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'robotrack_test')\gexec
SQL

echo "▸ Criando papéis (migrator/app), extensões, ownership e grants (roles.sql)…"
psql -v ON_ERROR_STOP=1 -d robotrack_dev  -f backend/db/roles.sql
psql -v ON_ERROR_STOP=1 -d robotrack_test -f backend/db/roles.sql

echo "▸ Migrando dev e test COMO MIGRATOR (structure.sql :sql)…"
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@${PGHOST}:${PGPORT}/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@${PGHOST}:${PGPORT}/robotrack_test"
(
  cd backend
  RAILS_ENV=development DATABASE_URL="$MIG_DEV"  bundle exec rails db:migrate
  RAILS_ENV=test        DATABASE_URL="$MIG_TEST" bundle exec rails db:migrate
)

echo "▸ Reaplicando roles.sql (REVOKEs append-only + ownership agora que as tabelas existem)…"
psql -v ON_ERROR_STOP=1 -d robotrack_dev  -f backend/db/roles.sql
psql -v ON_ERROR_STOP=1 -d robotrack_test -f backend/db/roles.sql

echo "▸ Seed de demonstração (best-effort; conecta como robotrack_app/RLS)…"
( cd backend && bundle exec rails db:seed ) \
  || echo "⚠ Seed pulado (não é crítico para subir o app)."

echo ""
echo "✅ Ambiente pronto."
echo "   Para subir o app:  bash .devcontainer/scripts/dev.sh"
echo "   Para o Claude Code: claude   (login interativo na 1ª vez)"
