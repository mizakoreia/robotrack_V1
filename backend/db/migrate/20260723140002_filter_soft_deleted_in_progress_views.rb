# frozen_string_literal: true

# hierarchy-soft-delete G1 (§2.1, §3.2, D5) — as quatro views de progresso passam
# a EXCLUIR `robots`/`cells`/`projects` arquivados (`deleted_at IS NOT NULL`).
#
# Antes desta change as views só filtravam `tasks` (`t.deleted_at IS NULL`); o
# lado da hierarquia entrava cru. Um robô arquivado continuaria na média da célula
# (`avg(rwp.value)`) e na contagem crua — arrastando o número de um nó que a tela
# não mostra mais. `CREATE OR REPLACE` preserva as colunas (só muda a cláusula), o
# `security_invoker` e o filtro de `tasks` já existentes.
#
# A partição `workspace` de `subtree_raw_completion` conta só `tasks` (sem
# hierarquia): as tarefas de um robô arquivado já saem porque o cascade
# (G2) marca `tasks.deleted_at` junto — a invariante do cascade cobre esse braço.
class FilterSoftDeletedInProgressViews < ActiveRecord::Migration[8.0]
  def up
    execute(view_sql(hierarchy_live: true))
  end

  def down
    execute(view_sql(hierarchy_live: false))
  end

  private

  # `hierarchy_live: true` inclui os filtros de `deleted_at` da hierarquia; `false`
  # é a definição anterior (só `tasks` filtrada) — a reversão restaura as views
  # como estavam.
  def view_sql(hierarchy_live:)
    r = hierarchy_live ? 'AND r.deleted_at IS NULL' : ''
    c = hierarchy_live ? 'AND c.deleted_at IS NULL' : ''
    where_r = hierarchy_live ? 'WHERE r.deleted_at IS NULL' : ''
    where_c = hierarchy_live ? 'WHERE c.deleted_at IS NULL' : ''
    where_p = hierarchy_live ? 'WHERE p.deleted_at IS NULL' : ''

    <<~SQL
      CREATE OR REPLACE VIEW robot_weighted_progress WITH (security_invoker = true) AS
      SELECT
        r.id           AS robot_id,
        r.workspace_id AS workspace_id,
        CASE
          WHEN count(t.id) = 0 THEN 0
          WHEN count(t.id) FILTER (WHERE t.status <> 'N/A') = 0 THEN 100
          WHEN COALESCE(sum(t.weight * 100) FILTER (WHERE t.status <> 'N/A'), 0) = 0 THEN 100
          ELSE round(
            (sum(t.weight * t.progress) FILTER (WHERE t.status <> 'N/A'))
            / (sum(t.weight * 100) FILTER (WHERE t.status <> 'N/A'))
            * 100
          )::int
        END AS value
      FROM robots r
      LEFT JOIN tasks t
        ON t.robot_id = r.id AND t.workspace_id = r.workspace_id AND t.deleted_at IS NULL
      #{where_r}
      GROUP BY r.id, r.workspace_id;

      CREATE OR REPLACE VIEW cell_weighted_progress WITH (security_invoker = true) AS
      SELECT
        c.id           AS cell_id,
        c.workspace_id AS workspace_id,
        COALESCE(round(avg(rwp.value)), 0)::int AS value
      FROM cells c
      LEFT JOIN robots r
        ON r.cell_id = c.id AND r.workspace_id = c.workspace_id #{r}
      LEFT JOIN robot_weighted_progress rwp
        ON rwp.robot_id = r.id AND rwp.workspace_id = c.workspace_id
      #{where_c}
      GROUP BY c.id, c.workspace_id;

      CREATE OR REPLACE VIEW project_weighted_progress WITH (security_invoker = true) AS
      SELECT
        p.id           AS project_id,
        p.workspace_id AS workspace_id,
        COALESCE(round(avg(cwp.value)), 0)::int AS value
      FROM projects p
      LEFT JOIN cells c
        ON c.project_id = p.id AND c.workspace_id = p.workspace_id #{c}
      LEFT JOIN cell_weighted_progress cwp
        ON cwp.cell_id = c.id AND cwp.workspace_id = p.workspace_id
      #{where_p}
      GROUP BY p.id, p.workspace_id;

      CREATE OR REPLACE VIEW subtree_raw_completion WITH (security_invoker = true) AS
        SELECT 'robot'::text AS scope_type, r.id AS scope_id, r.workspace_id,
               count(t.id) FILTER (WHERE t.status = 'Concluído')::int AS completed,
               count(t.id)::int AS total,
               CASE WHEN count(t.id) = 0 THEN 0
                    ELSE round(count(t.id) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(t.id) * 100)::int END AS percent
        FROM robots r
        LEFT JOIN tasks t ON t.robot_id = r.id AND t.workspace_id = r.workspace_id AND t.deleted_at IS NULL
        #{where_r}
        GROUP BY r.id, r.workspace_id
      UNION ALL
        SELECT 'cell', c.id, c.workspace_id,
               count(t.id) FILTER (WHERE t.status = 'Concluído')::int,
               count(t.id)::int,
               CASE WHEN count(t.id) = 0 THEN 0
                    ELSE round(count(t.id) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(t.id) * 100)::int END
        FROM cells c
        LEFT JOIN robots r ON r.cell_id = c.id AND r.workspace_id = c.workspace_id #{r}
        LEFT JOIN tasks t ON t.robot_id = r.id AND t.workspace_id = c.workspace_id AND t.deleted_at IS NULL
        #{where_c}
        GROUP BY c.id, c.workspace_id
      UNION ALL
        SELECT 'project', p.id, p.workspace_id,
               count(t.id) FILTER (WHERE t.status = 'Concluído')::int,
               count(t.id)::int,
               CASE WHEN count(t.id) = 0 THEN 0
                    ELSE round(count(t.id) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(t.id) * 100)::int END
        FROM projects p
        LEFT JOIN cells c ON c.project_id = p.id AND c.workspace_id = p.workspace_id #{c}
        LEFT JOIN robots r ON r.cell_id = c.id AND r.workspace_id = p.workspace_id #{r}
        LEFT JOIN tasks t ON t.robot_id = r.id AND t.workspace_id = p.workspace_id AND t.deleted_at IS NULL
        #{where_p}
        GROUP BY p.id, p.workspace_id
      UNION ALL
        SELECT 'workspace', t.workspace_id, t.workspace_id,
               count(*) FILTER (WHERE t.status = 'Concluído')::int,
               count(*)::int,
               CASE WHEN count(*) = 0 THEN 0
                    ELSE round(count(*) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(*) * 100)::int END
        FROM tasks t
        WHERE t.deleted_at IS NULL
        GROUP BY t.workspace_id;
    SQL
  end
end
