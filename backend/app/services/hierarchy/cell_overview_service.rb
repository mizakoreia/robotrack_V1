# frozen_string_literal: true

module Hierarchy
  # hierarchy-screens 2.3 (§3.4, D-A, D-C) — a Visão da CÉLULA: hub (robôs
  # configurados · tarefas concluídas) + cards de robô com badge = Aplicação e
  # rodapé `tasks_count`. Robô com 3 tarefas todas `N/A` tem `weighted_progress`
  # 100 (a ponderação ignora N/A) e `raw_completion.completed` 0 — a divergência do
  # D15 em pequeno. Orçamento: 3 queries (find + robôs com COUNT(tarefas vivas) +
  # contagem crua). `tasks_count` exclui soft-deletadas (mesmo join da view).
  module CellOverviewService
    module_function

    # `cell` já resolvido pelo controller (find sob RLS → 404 se ausente).
    def call(cell:)
      robots = robot_cards(cell.id)
      {
        counts: { configured_robots: robots.length },
        raw_completion: ProgressMetric.raw_completion(**OverviewService.raw_for('cell', cell.id)),
        robots: robots
      }
    end

    def robot_cards(cell_id)
      ::Robot
        .where(cell_id: cell_id)
        .joins('LEFT JOIN tasks ON tasks.robot_id = robots.id ' \
               'AND tasks.workspace_id = robots.workspace_id AND tasks.deleted_at IS NULL')
        .group('robots.id')
        .order('robots.position')
        .pluck('robots.id', 'robots.name', 'robots.application', 'robots.progress_cache', 'COUNT(tasks.id)')
        .map do |id, name, application, cache, tasks_count|
          {
            id: id, name: name, application: application,
            weighted_progress: ProgressMetric.weighted(cache), tasks_count: tasks_count
          }
        end
    end
  end
end
