# frozen_string_literal: true

# commissioning-hierarchy 1.2 (§1.1, D-H1, D-H3, D-H5, D-H7, D-H8, D-H9).
#
# Primeira tabela do domínio RoboTrack — e a dona das decisões que todo esquema
# posterior copia:
#
#   - PK `uuid` com default no BANCO e valor aceito do cliente (D1/D13): sem
#     isso, criar offline é estruturalmente impossível (§4.2).
#   - `UNIQUE (id, workspace_id)`: o alvo das FKs COMPOSTAS dos filhos — é o
#     que torna a divergência de tenant irrepresentável (D-H5).
#   - ordem manual: `position` inteira, contígua, 0-based por workspace, com a
#     unicidade DEFERRABLE para a renumeração em lote não passar por posições
#     fake (D-H3). Constraint, não índice avulso: só constraint é deferrable.
#   - `progress_cache` NASCE aqui com default '{}' (D5/D-H7) — a semântica é de
#     progress-rollup; a existência é obrigação desta migration.
#   - nome único por escopo case-insensitive + CHECK anti nome-só-de-espaços
#     (D-H8, o card sem rótulo do legado).
class CreateProjects < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE projects (
        id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id         uuid NOT NULL REFERENCES workspaces (id),
        name                 text NOT NULL,
        position             integer NOT NULL,
        progress_cache       jsonb NOT NULL DEFAULT '{}'::jsonb,
        progress_cached_at   timestamptz NULL,
        lock_version         integer NOT NULL DEFAULT 0,
        updated_by_person_id uuid NULL REFERENCES people (id) ON DELETE SET NULL,
        created_at           timestamptz NOT NULL DEFAULT now(),
        updated_at           timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_projects_name CHECK (length(btrim(name)) BETWEEN 1 AND 120),
        CONSTRAINT uq_projects_id_workspace UNIQUE (id, workspace_id),
        CONSTRAINT uq_projects_position UNIQUE (workspace_id, position)
          DEFERRABLE INITIALLY DEFERRED
      );

      CREATE UNIQUE INDEX index_projects_on_workspace_lower_name
        ON projects (workspace_id, lower(name));
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS projects;')
  end
end
