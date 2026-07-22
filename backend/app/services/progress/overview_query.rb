# frozen_string_literal: true

module Progress
  # progress-rollup 3.2/3.5 (§3.2, orçamento de query) — a Visão Geral em EXATAMENTE
  # 2 queries, constantes no nº de projetos:
  #
  #   1. a lista de projetos com `progress_cache` na própria linha (o anel de cada
  #      card NUNCA dispara query — lê a coluna já materializada);
  #   2. o hub global (contagem crua agregada no workspace) via
  #      `subtree_raw_completion`.
  #
  # Duas métricas, dois envelopes rotulados (D15): o anel de cada projeto é o
  # ponderado (§2.1); o hub é a contagem crua (§3.2). Elas divergem de propósito.
  module OverviewQuery
    module_function

    def call(workspace_id:)
      { projects: project_cards, raw_completion: workspace_raw(workspace_id) }
    end

    # 1 query — só as colunas do card, sem aninhar células/robôs.
    def project_cards
      ::Project.order(:position).pluck(:id, :name, :position, :progress_cache).map do |id, name, position, cache|
        { id: id, name: name, position: position, weighted_progress: ProgressMetric.weighted(cache) }
      end
    end

    # 1 query — o agregado do workspace na view da contagem crua.
    def workspace_raw(workspace_id)
      row = ::ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT completed, total, percent FROM subtree_raw_completion " \
           "WHERE scope_type = 'workspace' AND scope_id = ?", workspace_id]
        )
      )
      ProgressMetric.raw_completion(
        completed: row&.fetch('completed', 0) || 0,
        total: row&.fetch('total', 0) || 0,
        percent: row&.fetch('percent', 0) || 0
      )
    end
  end
end
