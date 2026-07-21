# frozen_string_literal: true

# commissioning-hierarchy 1.3 (§1.1, D-H5).
#
# A FK COMPOSTA (project_id, workspace_id) → projects (id, workspace_id) é o
# coração da tenancy desnormalizada: uma célula com workspace_id diferente do
# projeto dela é IRREPRESENTÁVEL — `UPDATE cells SET workspace_id = <outro>` no
# console é rejeitado pelo banco, não por convenção de model. `ON DELETE
# CASCADE`: excluir projeto leva as células num único DELETE (D-H6).
# Ordem e nome têm escopo pelo PAI (project_id), não pelo workspace.
class CreateCells < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE cells (
        id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id         uuid NOT NULL REFERENCES workspaces (id),
        project_id           uuid NOT NULL,
        name                 text NOT NULL,
        position             integer NOT NULL,
        progress_cache       jsonb NOT NULL DEFAULT '{}'::jsonb,
        progress_cached_at   timestamptz NULL,
        lock_version         integer NOT NULL DEFAULT 0,
        updated_by_person_id uuid NULL REFERENCES people (id) ON DELETE SET NULL,
        created_at           timestamptz NOT NULL DEFAULT now(),
        updated_at           timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_cells_name CHECK (length(btrim(name)) BETWEEN 1 AND 120),
        CONSTRAINT uq_cells_id_workspace UNIQUE (id, workspace_id),
        CONSTRAINT uq_cells_position UNIQUE (project_id, position)
          DEFERRABLE INITIALLY DEFERRED,
        CONSTRAINT fk_cells_project_same_workspace
          FOREIGN KEY (project_id, workspace_id)
          REFERENCES projects (id, workspace_id) ON DELETE CASCADE
      );

      CREATE UNIQUE INDEX index_cells_on_project_lower_name
        ON cells (project_id, lower(name));

      -- Exigido pela guarda de esquema de tenancy (custo de RLS) e usado por
      -- qualquer listagem por workspace.
      CREATE INDEX index_cells_on_workspace_id ON cells (workspace_id);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS cells;')
  end
end
