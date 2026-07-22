# frozen_string_literal: true

# hierarchy-soft-delete G1 (§2.9, D1, D2) — o soft-delete de `projects`/`cells`/
# `robots`. Excluir um nó da hierarquia passa a ARQUIVAR (`deleted_at`), nunca
# `DELETE` físico: a trilha de avanços (`task_advances`) é imutável e trava as
# tarefas com FK `ON DELETE RESTRICT`, então apagar um robô com progresso daria
# 500. `tasks` já resolveu assim para si; aqui o padrão sobe para os três níveis.
#
# Três invariantes NO BANCO:
#   1. `deleted_at` nullable em cada tabela (o nó some da leitura quando preenchido;
#      o `default_scope` dos models espelha `Task`);
#   2. o índice único de nome por escopo vira PARCIAL (`WHERE deleted_at IS NULL`)
#      — arquivar "R-014" LIBERA criar um novo "R-014" ativo na mesma célula (D2);
#   3. `position` vira NULLABLE (D1): a unicidade de posição é uma constraint
#      DEFERRABLE (a renumeração em lote passa por posições transitórias), e um
#      índice parcial NÃO pode dar suporte a constraint deferrable. Zerar a
#      `position` para NULL no soft-delete tira o nó arquivado do domínio do
#      UNIQUE (múltiplos NULL são permitidos) sem tocar na constraint — a
#      renumeração dos irmãos vivos nunca colide com o arquivado.
#
# Índice parcial de leitura viva por nível: o caminho quente lê só `deleted_at IS
# NULL`; o índice parcial mantém a varredura barata e não cresce com o arquivo.
class AddDeletedAtToHierarchy < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE projects ADD COLUMN deleted_at timestamptz NULL;
      ALTER TABLE cells    ADD COLUMN deleted_at timestamptz NULL;
      ALTER TABLE robots   ADD COLUMN deleted_at timestamptz NULL;

      ALTER TABLE projects ALTER COLUMN position DROP NOT NULL;
      ALTER TABLE cells    ALTER COLUMN position DROP NOT NULL;
      ALTER TABLE robots   ALTER COLUMN position DROP NOT NULL;

      -- Unicidade de nome só entre os VIVOS (D2).
      DROP INDEX index_projects_on_workspace_lower_name;
      CREATE UNIQUE INDEX index_projects_on_workspace_lower_name
        ON projects (workspace_id, lower(name)) WHERE deleted_at IS NULL;

      DROP INDEX index_cells_on_project_lower_name;
      CREATE UNIQUE INDEX index_cells_on_project_lower_name
        ON cells (project_id, lower(name)) WHERE deleted_at IS NULL;

      DROP INDEX index_robots_on_cell_lower_name;
      CREATE UNIQUE INDEX index_robots_on_cell_lower_name
        ON robots (cell_id, lower(name)) WHERE deleted_at IS NULL;

      -- Leitura viva por workspace (o default_scope filtra deleted_at IS NULL).
      CREATE INDEX index_projects_on_workspace_id_live
        ON projects (workspace_id) WHERE deleted_at IS NULL;
      CREATE INDEX index_cells_on_workspace_id_live
        ON cells (workspace_id) WHERE deleted_at IS NULL;
      CREATE INDEX index_robots_on_workspace_id_live
        ON robots (workspace_id) WHERE deleted_at IS NULL;
    SQL
  end

  def down
    # Restaurar `position NOT NULL` e a unicidade total de nome só é seguro se
    # NENHUM nó estiver arquivado (linhas arquivadas têm position NULL e nome que
    # pode colidir com um vivo). Fail-closed em vez de corromper.
    if select_value(<<~SQL).to_i.positive?
      SELECT count(*) FROM (
        SELECT 1 FROM projects WHERE deleted_at IS NOT NULL
        UNION ALL SELECT 1 FROM cells WHERE deleted_at IS NOT NULL
        UNION ALL SELECT 1 FROM robots WHERE deleted_at IS NOT NULL
      ) s
    SQL
      raise ActiveRecord::IrreversibleMigration,
            'há nós arquivados (deleted_at); reverter perderia a integridade de posição/nome'
    end

    execute(<<~SQL)
      DROP INDEX IF EXISTS index_projects_on_workspace_id_live;
      DROP INDEX IF EXISTS index_cells_on_workspace_id_live;
      DROP INDEX IF EXISTS index_robots_on_workspace_id_live;

      DROP INDEX index_robots_on_cell_lower_name;
      CREATE UNIQUE INDEX index_robots_on_cell_lower_name ON robots (cell_id, lower(name));
      DROP INDEX index_cells_on_project_lower_name;
      CREATE UNIQUE INDEX index_cells_on_project_lower_name ON cells (project_id, lower(name));
      DROP INDEX index_projects_on_workspace_lower_name;
      CREATE UNIQUE INDEX index_projects_on_workspace_lower_name ON projects (workspace_id, lower(name));

      ALTER TABLE robots   ALTER COLUMN position SET NOT NULL;
      ALTER TABLE cells    ALTER COLUMN position SET NOT NULL;
      ALTER TABLE projects ALTER COLUMN position SET NOT NULL;

      ALTER TABLE robots   DROP COLUMN deleted_at;
      ALTER TABLE cells    DROP COLUMN deleted_at;
      ALTER TABLE projects DROP COLUMN deleted_at;
    SQL
  end
end
