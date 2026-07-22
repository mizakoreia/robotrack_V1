# frozen_string_literal: true

module Progress
  # progress-rollup 4.1–4.4 (§D5.d, D2) — o detector honesto do cache velho.
  #
  # A ATUALIDADE de `progress_cache` não tem constraint; este job é a terceira
  # camada (depois do ponto de escrita único e do sweep). Por workspace, sob RLS
  # (`app.current_workspace_id` setado a cada iteração — um job fora de RLS
  # reconciliaria ENTRE tenants, D2): compara cache vs. views nos três níveis,
  # CORRIGE as linhas divergentes e ALERTA com o valor antigo.
  #
  # `perform(workspace_id)` reconcilia UM workspace — é o modelo de fan-out do
  # cron: `delivery-and-observability` (dona do agendamento) enfileira um job por
  # workspace. A enumeração de todos os tenants é operação privilegiada (cruza
  # RLS) e pertence àquele scheduler, não ao runtime `robotrack_app`.
  class ReconciliationJob
    include Sidekiq::Job if defined?(Sidekiq::Job)

    LEVELS = [
      ['robot',   'robots',   'robot_weighted_progress',   'robot_id'],
      ['cell',    'cells',    'cell_weighted_progress',    'cell_id'],
      ['project', 'projects', 'project_weighted_progress', 'project_id']
    ].freeze

    def perform(workspace_id)
      self.class.require_channel!
      self.class.reconcile_workspace(workspace_id)
    end

    class << self
      # 4.3 — em produção, a ausência do canal FALHA (não corrige em silêncio,
      # deixando o usuário ver número errado até alguém acordar).
      def require_channel!
        return if defined?(::Observability::Alert)
        return unless Rails.env.production?

        raise 'Progress::ReconciliationJob exige a interface Observability::Alert ' \
              '(capacidade delivery-and-observability) em produção — canal de alerta ausente.'
      end

      def reconcile_workspace(workspace_id)
        Tenant.with(workspace_id: workspace_id, user_id: nil) do
          divergences = collect
          next if divergences.empty? # 4.6 — execução limpa NÃO alerta (nem row_count: 0)

          # 4.2 — corrige tudo em massa (3 statements) DEPOIS de coletar os valores
          # antigos, e alerta cada linha com o `cached` capturado.
          ::Progress::BulkRecompute.call(workspace_id: workspace_id)
          divergences.each do |d|
            ::Progress::DivergenceReporter.report(
              workspace_id: workspace_id, level: d[:level], scope_id: d[:scope_id],
              cached: d[:cached], computed: d[:computed], row_count: divergences.size
            )
          end
        end
      end

      # Coleta as linhas divergentes dos 3 níveis (sob a RLS do workspace atual).
      def collect
        conn = ActiveRecord::Base.connection
        LEVELS.flat_map do |level, table, view, key|
          rows = conn.select_all(<<~SQL)
            SELECT t.id AS scope_id, t.progress_cache AS cached, v.value AS computed
            FROM #{table} t
            JOIN #{view} v ON v.#{key} = t.id
            WHERE t.progress_cache <> v.value
          SQL
          rows.map do |r|
            { level: level, scope_id: r['scope_id'], cached: r['cached'].to_i, computed: r['computed'].to_i }
          end
        end
      end
    end
  end
end
