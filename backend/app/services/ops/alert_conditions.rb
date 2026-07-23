# frozen_string_literal: true

module Ops
  # Condições operacionais de alerta (delivery-and-observability 5.3). A LÓGICA de
  # decisão é pura e testável; a coleta das métricas e o rastreio das janelas
  # sustentadas (5xx em 5 min, fila em 10 min) são de wiring de monitoramento
  # (deploy). Uma fila que sobe a 1.200 e drena em 4 min NÃO dispara; a que fica
  # 11 min dispara — por isso a entrada é a MÉTRICA SUSTENTADA, não a instantânea.
  module AlertConditions
    ERROR_RATE_THRESHOLD = 0.01   # 1%
    QUEUE_DEPTH_THRESHOLD = 1_000

    module_function

    # `snapshot` já traz as janelas resolvidas pelo coletor:
    #   error_rate_5m:              fração de 5xx nos últimos 5 min
    #   queue_depth_sustained_10m:  profundidade sustentada por >= 10 min (0 se drenou)
    #   dead_count:                 jobs no dead set
    #   cable_publish_failed:       bool — falha de publicação no Cable
    #   release_failed:             bool — falha da fase de release
    def evaluate(snapshot)
      alerts = []

      if snapshot[:error_rate_5m].to_f > ERROR_RATE_THRESHOLD
        alerts << alert('http_5xx_rate_high', :critical,
                        "Taxa de 5xx #{(snapshot[:error_rate_5m] * 100).round(2)}% > 1% em 5 min")
      end

      if snapshot[:queue_depth_sustained_10m].to_i > QUEUE_DEPTH_THRESHOLD
        alerts << alert('sidekiq_queue_backlog', :warning,
                        "Fila em #{snapshot[:queue_depth_sustained_10m]} jobs por mais de 10 min")
      end

      if snapshot[:dead_count].to_i.positive?
        alerts << alert('sidekiq_dead_set', :warning, "#{snapshot[:dead_count]} job(s) no dead set")
      end

      alerts << alert('cable_publish_failure', :critical, 'Falha de publicação no ActionCable') if snapshot[:cable_publish_failed]
      alerts << alert('release_phase_failure', :critical, 'Falha da fase de release (bin/release)') if snapshot[:release_failed]

      alerts
    end

    def alert(key, severity, message)
      { key: key, severity: severity, message: message }
    end

    # Dispara os alertas avaliados pelo canal único.
    def raise_all(snapshot)
      evaluate(snapshot).each { |a| Ops::AlertService.raise_alert(**a) }
    end
  end
end
