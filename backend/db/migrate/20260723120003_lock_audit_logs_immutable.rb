# frozen_string_literal: true

# audit-log G1 (§4.1 inv. 3, Decisão 1 — camadas 1 e 2 da imutabilidade).
#
# A invariante 3 é a ÚNICA cujo adversário declarado é o próprio dono do dado, logo
# não pode morar em nada que o dono controle em runtime (nem model, nem console):
#   1. `REVOKE UPDATE, DELETE` do papel de app — nega todo DML de mutação vindo do
#      runtime, inclusive `update_column`/`update_all`/`delete_all` e o `rails
#      console` de produção (mesma credencial). Replicado em `db/roles.sql` porque
#      `pg_dump -x` (structure.sql) OMITE GRANT/REVOKE.
#   2. Trigger `BEFORE UPDATE OR DELETE ... FOR EACH ROW` com `RAISE EXCEPTION`
#      incondicional — pega o caminho que o REVOKE não pega: o DONO da tabela e
#      superusuário (ex.: um `rails db:migrate` acidental). No PARENT particionado
#      a trigger de linha cascateia às partições (PG 13+). `TRUNCATE`
#      (DatabaseCleaner) NÃO dispara trigger de linha → a suíte roda; `DETACH`/`DROP`
#      de partição (retenção, G7) idem, e é por isso que a poda é DDL, não DELETE.
class LockAuditLogsImmutable < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      REVOKE UPDATE, DELETE ON audit_logs FROM robotrack_app;

      CREATE OR REPLACE FUNCTION audit_logs_forbid_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'audit_logs é append-only: % proibido (audit-log §4.1 inv. 3)', TG_OP;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_audit_logs_immutable
        BEFORE UPDATE OR DELETE ON audit_logs
        FOR EACH ROW EXECUTE FUNCTION audit_logs_forbid_mutation();
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
      DROP FUNCTION IF EXISTS audit_logs_forbid_mutation();
      GRANT UPDATE, DELETE ON audit_logs TO robotrack_app;
    SQL
  end
end
