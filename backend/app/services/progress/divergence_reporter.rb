# frozen_string_literal: true

module Progress
  # progress-rollup 4.2/4.3 (§D5.d) — o reporte de divergência do cache. O valor
  # ANTIGO (`cached`) é a evidência de qual caminho de escrita esqueceu a cascata;
  # perdê-lo torna o alerta inacionável, então ele viaja no evento.
  #
  # O CANAL de alerta e a MÉTRICA são de `delivery-and-observability` (EXECUCAO
  # decisão 3): consumimos `Observability::Alert.notify` e a métrica SE existirem;
  # senão, log estruturado (o evento existe, o canal é o que falta). A checagem de
  # boot que EXIGE o canal em produção mora em `ReconciliationJob.require_channel!`.
  module DivergenceReporter
    module_function

    def report(workspace_id:, level:, scope_id:, cached:, computed:, row_count:)
      payload = {
        workspace_id: workspace_id, level: level, scope_id: scope_id,
        cached: cached, computed: computed, row_count: row_count
      }
      # Evento estruturado — a fonte única que o teste observa e que o canal
      # consome. `instrument` para os assinantes (realtime/observabilidade).
      ActiveSupport::Notifications.instrument('progress_cache.divergence', payload)
      Rails.logger.warn({ event: 'progress_cache.divergence', **payload }.to_json)

      notify_channel(payload)
      increment_metric(workspace_id)
    end

    def notify_channel(payload)
      return unless defined?(::Observability::Alert)

      ::Observability::Alert.notify(event: 'progress_cache.divergence', severity: :warning, payload: payload)
    end

    def increment_metric(workspace_id)
      return unless defined?(::Observability::Metrics)

      ::Observability::Metrics.increment('progress_cache_divergence_total',
                                         labels: { workspace_id: workspace_id })
    end
  end
end
