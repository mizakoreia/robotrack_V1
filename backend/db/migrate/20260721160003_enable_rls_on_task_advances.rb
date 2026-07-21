# frozen_string_literal: true

# progress-advances G1 / Migration B (§4.1 inv. 1, D2, D-IMUT).
#
# RLS com policies APENAS de SELECT e INSERT — NENHUMA de UPDATE/DELETE. É a 1ª
# das três camadas de imutabilidade (D-IMUT): sem policy de UPDATE/DELETE, o
# Postgres nega essas operações por omissão para o role da aplicação, e um
# re-GRANT futuro (que uma policy FOR ALL reabriria) continua sem porta. A policy
# de SELECT chama-se `tenant_isolation` para satisfazer a guarda de tenancy.
class EnableRlsOnTaskAdvances < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE task_advances ENABLE ROW LEVEL SECURITY;
      ALTER TABLE task_advances FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON task_advances FOR SELECT
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      CREATE POLICY tenant_isolation_insert ON task_advances FOR INSERT
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute(<<~SQL)
      DROP POLICY IF EXISTS tenant_isolation_insert ON task_advances;
      DROP POLICY IF EXISTS tenant_isolation ON task_advances;
      ALTER TABLE task_advances NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE task_advances DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
