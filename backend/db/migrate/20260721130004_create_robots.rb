# frozen_string_literal: true

# commissioning-hierarchy 1.4 (§1.1, §1.2, D-H5, D-H10).
#
# `application` é `text` + CHECK dos SEIS literais pt-BR da §1.2 — a string é a
# chave de junção com `appFilters` do catálogo (§1.3) e com o export legado;
# traduzir para símbolo exigiria mapa de ida-e-volta em três lugares. CHECK e
# não `CREATE TYPE`: adicionar valor a enum Postgres não é reversível em
# migration transacional, e §1.2 pode ganhar aplicação nova.
# `INSERT ... application = 'Pintura'` falha NO BANCO, não só no model.
class CreateRobots < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE robots (
        id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id         uuid NOT NULL REFERENCES workspaces (id),
        cell_id              uuid NOT NULL,
        name                 text NOT NULL,
        application          text NOT NULL DEFAULT 'Misto / Geral',
        position             integer NOT NULL,
        progress_cache       jsonb NOT NULL DEFAULT '{}'::jsonb,
        progress_cached_at   timestamptz NULL,
        lock_version         integer NOT NULL DEFAULT 0,
        updated_by_person_id uuid NULL REFERENCES people (id) ON DELETE SET NULL,
        created_at           timestamptz NOT NULL DEFAULT now(),
        updated_at           timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_robots_name CHECK (length(btrim(name)) BETWEEN 1 AND 120),
        CONSTRAINT chk_robots_application CHECK (
          application IN ('Misto / Geral','Solda Ponto','Solda MIG','Handling','Sealing','Outros')
        ),
        CONSTRAINT uq_robots_id_workspace UNIQUE (id, workspace_id),
        CONSTRAINT uq_robots_position UNIQUE (cell_id, position)
          DEFERRABLE INITIALLY DEFERRED,
        CONSTRAINT fk_robots_cell_same_workspace
          FOREIGN KEY (cell_id, workspace_id)
          REFERENCES cells (id, workspace_id) ON DELETE CASCADE
      );

      CREATE UNIQUE INDEX index_robots_on_cell_lower_name
        ON robots (cell_id, lower(name));

      CREATE INDEX index_robots_on_workspace_id ON robots (workspace_id);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS robots;')
  end
end
