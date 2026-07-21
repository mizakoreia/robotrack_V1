# frozen_string_literal: true

# commissioning-hierarchy 1.5 (§4.1 inv. 1, D2, D-H5).
#
# ENABLE + FORCE nas três tabelas na MESMA onda de migrations que as criou —
# habilitar depois abriria a janela em que a tabela existe sem isolamento (e é
# exatamente a janela em que alguém roda um seed). `FORCE` vincula até o dono
# (robotrack_migrator). `current_setting(..., true)` sem a variável devolve
# NULL → predicado NULL → nenhuma linha: fail-closed, o padrão da Onda 1.
# `SELECT count(*) FROM projects` sem contexto devolve 0, não a tabela.
class EnableRlsOnHierarchy < ActiveRecord::Migration[8.0]
  TABLES = %w[projects cells robots].freeze

  def up
    TABLES.each do |table|
      execute(<<~SQL)
        ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
        ALTER TABLE #{table} FORCE  ROW LEVEL SECURITY;

        CREATE POLICY tenant_isolation ON #{table}
          USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
          WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
      SQL
    end
  end

  def down
    TABLES.reverse_each do |table|
      execute(<<~SQL)
        DROP POLICY IF EXISTS tenant_isolation ON #{table};
        ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY;
        ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;
      SQL
    end
  end
end
