# frozen_string_literal: true

# progress-advances G1 / Migration C (§4.1 inv. 3, D-IMUT).
#
# Camadas 2 e 3 da imutabilidade, DEPOIS de A e B (senão as migrations seguintes
# esbarrariam no trigger):
#   2. `REVOKE UPDATE, DELETE` do role da aplicação — negação explícita, para não
#      depender de ninguém não desligar RLS numa migration futura. Replicado em
#      `db/roles.sql` porque `pg_dump -x` (structure.sql) OMITE GRANT/REVOKE.
#   3. Trigger `BEFORE UPDATE OR DELETE` com `RAISE EXCEPTION` — pega o caminho que
#      as duas anteriores não pegam: migration/psql rodando como DONO da tabela.
#      TRUNCATE (DatabaseCleaner) NÃO dispara trigger de linha, então a suíte roda.
class LockTaskAdvancesImmutable < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      REVOKE UPDATE, DELETE ON task_advances FROM robotrack_app;

      CREATE OR REPLACE FUNCTION task_advances_forbid_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'task_advances é append-only: % proibido (progress-advances D-IMUT)', TG_OP;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_task_advances_immutable
        BEFORE UPDATE OR DELETE ON task_advances
        FOR EACH ROW EXECUTE FUNCTION task_advances_forbid_mutation();
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS trg_task_advances_immutable ON task_advances;
      DROP FUNCTION IF EXISTS task_advances_forbid_mutation();
      GRANT UPDATE, DELETE ON task_advances TO robotrack_app;
    SQL
  end
end
