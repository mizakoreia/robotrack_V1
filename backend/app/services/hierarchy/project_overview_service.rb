# frozen_string_literal: true

module Hierarchy
  # hierarchy-screens 2.2 (§3.3, D-A, D-C) — a Visão do PROJETO: hub (células
  # configuradas · robôs analisados · tarefas concluídas) + cards de célula com
  # `robots_count`. Projeto sem células → `cells: []` e hub zerado, NUNCA 404
  # (o 404 é só para projeto ausente/cross-tenant, resolvido pela RLS no controller).
  # Orçamento: 3 queries (find + células com COUNT(robôs) + contagem crua). O total
  # de robôs analisados é DERIVADO da soma dos `robots_count` — sem 4ª query.
  module ProjectOverviewService
    module_function

    # `project` já resolvido pelo controller (find sob RLS → 404 se ausente).
    def call(project:)
      cells = cell_cards(project.id)
      analyzed_robots = cells.sum { |c| c[:robots_count] }
      {
        id: project.id, name: project.name, # cabeçalho da tela de Projeto
        counts: { configured_cells: cells.length, analyzed_robots: analyzed_robots },
        raw_completion: ProgressMetric.raw_completion(**OverviewService.raw_for('project', project.id)),
        cells: cells
      }
    end

    def cell_cards(project_id)
      # hierarchy-soft-delete D6 — robô arquivado filtrado no ON do LEFT JOIN, para
      # a célula viva com só robôs arquivados ainda aparecer com `robots_count = 0`.
      ::Cell
        .where(project_id: project_id)
        .joins('LEFT OUTER JOIN robots ON robots.cell_id = cells.id AND robots.deleted_at IS NULL')
        .group('cells.id')
        .order('cells.position')
        .pluck('cells.id', 'cells.name', 'cells.progress_cache', 'COUNT(robots.id)', 'cells.lock_version')
        .map do |id, name, cache, robots_count, lock_version|
          # `lock_version` acompanha o card para a tela renomear a célula sem um
          # segundo fetch (o PATCH exige a versão; hierarchy-screens 5.2).
          {
            id: id, name: name, weighted_progress: ProgressMetric.weighted(cache),
            robots_count: robots_count, lock_version: lock_version
          }
        end
    end
  end
end
