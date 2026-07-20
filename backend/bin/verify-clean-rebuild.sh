#!/usr/bin/env bash
# workspace-tenancy 6.5 — verificação de rebuild limpo.
#
# Reconstrói o banco de teste do ZERO a partir de db/structure.sql
# (db:drop/create/schema:load como robotrack_migrator), reaplica os papéis/grants
# e roda a suíte de isolamento sobre o banco reconstruído. Se o structure.sql não
# carregar a RLS (1.1 incompleta), os cenários de negação falham aqui em vez de
# um banco nascer sem isolamento e verde. Ver db/PROVISIONING.md.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${MIGRATION_DATABASE_URL:=postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test}"
: "${SUPERUSER:=robotrack_user}"
: "${TEST_DB:=robotrack_test}"

echo "== db:drop / db:create / db:schema:load (como migrator) =="
RAILS_ENV=test DATABASE_URL="$MIGRATION_DATABASE_URL" \
  bundle exec rails db:drop db:create db:schema:load

echo "== reaplica papéis e grants (o recreate apaga ownership/grants) =="
psql -U "$SUPERUSER" -d "$TEST_DB" -f db/roles.sql >/dev/null

echo "== suíte de isolamento sobre o banco reconstruído (como robotrack_app) =="
bundle exec rspec spec/tenancy

echo "OK — o banco reconstruído do structure.sql nasce isolado."
