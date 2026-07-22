# frozen_string_literal: true

# progress-rollup 1.2–1.4 (§2.1, §3.2, D5.a/D5.e) — as DUAS métricas em SQL, o
# único lugar onde cada uma é definida (sem gêmeo Ruby/TS).
#
# `security_invoker = true` (PG15+): as views acessam as tabelas com a RLS do
# INVOCADOR (robotrack_app), não do dono — cada view já sai filtrada por
# `app.current_workspace_id`. Todo cálculo em `numeric`, `ROUND` em `numeric`
# (nunca `float`), e arredondamento em CADA nível (D5.a).
#
# Literais do enum pt-BR (EXECUCAO decisão 2): válida = `status <> 'N/A'`,
# concluída = `status = 'Concluído'`. Tarefas soft-deletadas (deleted_at) fora.
class CreateProgressViews < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      -- §2.1 robô: sem tarefas → 0; com tarefas, 0 válidas → 100; peso total 0 → 100
      -- (nada a cumprir); senão round(Σ(peso×prog)/Σ(peso×100)×100).
      CREATE VIEW robot_weighted_progress WITH (security_invoker = true) AS
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
      GROUP BY r.id, r.workspace_id;

      -- §2.1 célula: média aritmética SIMPLES dos robôs já arredondados. Cada robô
      -- pesa igual (a ponderação PARA na fronteira do robô). Sem robôs → 0.
      CREATE VIEW cell_weighted_progress WITH (security_invoker = true) AS
      SELECT
        c.id           AS cell_id,
        c.workspace_id AS workspace_id,
        COALESCE(round(avg(rwp.value)), 0)::int AS value
      FROM cells c
      LEFT JOIN robots r
        ON r.cell_id = c.id AND r.workspace_id = c.workspace_id
      LEFT JOIN robot_weighted_progress rwp
        ON rwp.robot_id = r.id AND rwp.workspace_id = c.workspace_id
      GROUP BY c.id, c.workspace_id;

      -- §2.1 projeto: média simples das células já arredondadas. Sem células → 0.
      CREATE VIEW project_weighted_progress WITH (security_invoker = true) AS
      SELECT
        p.id           AS project_id,
        p.workspace_id AS workspace_id,
        COALESCE(round(avg(cwp.value)), 0)::int AS value
      FROM projects p
      LEFT JOIN cells c
        ON c.project_id = p.id AND c.workspace_id = p.workspace_id
      LEFT JOIN cell_weighted_progress cwp
        ON cwp.cell_id = c.id AND cwp.workspace_id = p.workspace_id
      GROUP BY p.id, p.workspace_id;

      -- §3.2 contagem crua, agregável em qualquer nível. `N/A` NO DENOMINADOR
      -- (D5.e): total conta todas as tarefas não-deletadas; completed só as
      -- 'Concluído'. Escopo sem tarefas → 0/0/0.
      CREATE VIEW subtree_raw_completion WITH (security_invoker = true) AS
        SELECT 'robot'::text AS scope_type, r.id AS scope_id, r.workspace_id,
               count(t.id) FILTER (WHERE t.status = 'Concluído')::int AS completed,
               count(t.id)::int AS total,
               CASE WHEN count(t.id) = 0 THEN 0
                    ELSE round(count(t.id) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(t.id) * 100)::int END AS percent
        FROM robots r
        LEFT JOIN tasks t ON t.robot_id = r.id AND t.workspace_id = r.workspace_id AND t.deleted_at IS NULL
        GROUP BY r.id, r.workspace_id
      UNION ALL
        SELECT 'cell', c.id, c.workspace_id,
               count(t.id) FILTER (WHERE t.status = 'Concluído')::int,
               count(t.id)::int,
               CASE WHEN count(t.id) = 0 THEN 0
                    ELSE round(count(t.id) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(t.id) * 100)::int END
        FROM cells c
        LEFT JOIN robots r ON r.cell_id = c.id AND r.workspace_id = c.workspace_id
        LEFT JOIN tasks t ON t.robot_id = r.id AND t.workspace_id = c.workspace_id AND t.deleted_at IS NULL
        GROUP BY c.id, c.workspace_id
      UNION ALL
        SELECT 'project', p.id, p.workspace_id,
               count(t.id) FILTER (WHERE t.status = 'Concluído')::int,
               count(t.id)::int,
               CASE WHEN count(t.id) = 0 THEN 0
                    ELSE round(count(t.id) FILTER (WHERE t.status = 'Concluído')::numeric
                               / count(t.id) * 100)::int END
        FROM projects p
        LEFT JOIN cells c ON c.project_id = p.id AND c.workspace_id = p.workspace_id
        LEFT JOIN robots r ON r.cell_id = c.id AND r.workspace_id = p.workspace_id
        LEFT JOIN tasks t ON t.robot_id = r.id AND t.workspace_id = p.workspace_id AND t.deleted_at IS NULL
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

      -- D5.e — o índice parcial que resolve a contagem crua por índice.
      CREATE INDEX idx_tasks_ws_robot_status
        ON tasks (workspace_id, robot_id, status) WHERE deleted_at IS NULL;
    SQL

    grant_select_to_app
  end

  def down
    execute(<<~SQL)
      DROP INDEX IF EXISTS idx_tasks_ws_robot_status;
      DROP VIEW IF EXISTS subtree_raw_completion;
      DROP VIEW IF EXISTS project_weighted_progress;
      DROP VIEW IF EXISTS cell_weighted_progress;
      DROP VIEW IF EXISTS robot_weighted_progress;
    SQL
  end

  private

  # As views são novas objetos: o runtime (robotrack_app) precisa de SELECT. O
  # `GRANT ON ALL TABLES` do roles.sql cobre no rebuild, mas concedemos aqui para
  # a migration bastar por si num banco já provisionado.
  def grant_select_to_app
    execute(<<~SQL)
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'robotrack_app') THEN
          GRANT SELECT ON robot_weighted_progress, cell_weighted_progress,
                          project_weighted_progress, subtree_raw_completion
            TO robotrack_app;
        END IF;
      END $$;
    SQL
  end
end
