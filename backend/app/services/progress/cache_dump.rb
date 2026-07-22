# frozen_string_literal: true

module Progress
  # progress-rollup 5.1 (§4.4) — dump do `progress_cache` dos três níveis ANTES de
  # qualquer recálculo em massa sobre dado importado. Sem ele, um bug nas views
  # tornaria o estado anterior irrecuperável (o `BulkRecompute` reescreve a
  # coluna). O dump é verificável por contagem de linhas por nível.
  #
  # Roda sob a RLS do workspace (D2): só dumpa o tenant informado.
  module CacheDump
    module_function

    LEVELS = { 'robot' => 'robots', 'cell' => 'cells', 'project' => 'projects' }.freeze

    # Escreve JSONL em `path`, uma linha por escopo, e devolve a contagem por nível.
    def call(workspace_id:, path:)
      counts = Hash.new(0)
      File.open(path, 'w') do |file|
        Tenant.with(workspace_id: workspace_id, user_id: nil) do
          LEVELS.each do |level, table|
            ActiveRecord::Base.connection.select_all(
              # hierarchy-soft-delete D6 — não dumpa nós arquivados (cache stale,
              # irrelevante; o `default_scope` não alcança este SQL cru).
              "SELECT id, workspace_id, progress_cache FROM #{table} WHERE deleted_at IS NULL"
            ).each do |row|
              file.puts({ level: level, scope_id: row['id'], workspace_id: row['workspace_id'],
                          progress_cache: row['progress_cache'].to_i }.to_json)
              counts[level] += 1
            end
          end
        end
      end
      counts
    end
  end
end
