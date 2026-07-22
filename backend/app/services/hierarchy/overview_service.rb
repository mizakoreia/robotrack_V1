# frozen_string_literal: true

module Hierarchy
  # hierarchy-screens 2.1 (§3.2, D-A, D-C) — a Visão Geral do WORKSPACE. Estende a
  # forma leve de `progress-rollup` (mantém `raw_completion` no topo e o anel
  # ponderado por projeto) somando o que a tela precisa: `cells_count` por card e
  # as contagens do hub (projetos ativos, robôs analisados). Orçamento: 3 queries
  # CONSTANTES no nº de projetos (D-C) — o anel lê `progress_cache` da coluna, nunca
  # recalcula por linha.
  #
  #   Q1  projetos + COUNT(células)         → cards + projetos ativos
  #   Q2  contagem crua do workspace (view) → hub
  #   Q3  COUNT(robôs)                      → robôs analisados
  module OverviewService
    module_function

    def call(workspace_id:)
      projects = project_cards
      {
        counts: { active_projects: projects.length, analyzed_robots: ::Robot.count },
        raw_completion: ProgressMetric.raw_completion(**raw_for('workspace', workspace_id)),
        projects: projects
      }
    end

    # Q1 — uma query com GROUP: cards do projeto com a contagem de células. O anel
    # é o ponderado lido de `progress_cache` (nunca aninha células/robôs/tarefas).
    def project_cards
      # hierarchy-soft-delete D6 — o filtro de célula arquivada mora no ON do LEFT
      # JOIN (não no WHERE): assim um projeto vivo com SÓ células arquivadas ainda
      # aparece com `cells_count = 0`, em vez de sumir. Projeto é a relação primária
      # (o `default_scope` já exclui projeto arquivado).
      ::Project
        .joins('LEFT OUTER JOIN cells ON cells.project_id = projects.id AND cells.deleted_at IS NULL')
        .group('projects.id')
        .order('projects.position')
        .pluck('projects.id', 'projects.name', 'projects.progress_cache', 'COUNT(cells.id)')
        .map do |id, name, cache, cells_count|
          { id: id, name: name, weighted_progress: ProgressMetric.weighted(cache), cells_count: cells_count }
        end
    end

    # Leitura da view de contagem crua num escopo. Escopo sem tarefas → 0/0/0
    # (nunca NaN nem divisão por zero, §3.2). Reusada pelos overviews de nível.
    def raw_for(scope_type, scope_id)
      row = ::ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array(
          ['SELECT completed, total, percent FROM subtree_raw_completion ' \
           'WHERE scope_type = ? AND scope_id = ?', scope_type, scope_id]
        )
      )
      {
        completed: row&.fetch('completed', 0) || 0,
        total: row&.fetch('total', 0) || 0,
        percent: row&.fetch('percent', 0) || 0
      }
    end
  end
end
