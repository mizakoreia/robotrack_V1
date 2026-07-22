# frozen_string_literal: true

# progress-rollup / D15 — a MÉTRICA como valor de primeira classe, não um número
# solto. Duas métricas coexistem de propósito (§2.1 ponderada, §3.2 contagem
# crua) e NENHUM número de progresso é exposto sem dizer qual é.
#
# Fonte única dos rótulos (D14). G6 move as strings para
# `config/locales/pt-BR.progress.yml`; por ora já estão centralizadas aqui —
# nenhum literal de rótulo vive numa entity ou service.
module ProgressMetric
  WEIGHTED  = 'weighted'
  RAW_COUNT = 'raw_count'
  METRICS   = [WEIGHTED, RAW_COUNT].freeze

  # Métrica fora do enum fechado levanta ANTES de serializar (labeling spec). O
  # rótulo vem do locale pt-BR (D14) — `raise: true` faz uma chave ausente falhar
  # em TESTE (completude de locale), não renderizar a chave crua ao usuário.
  def self.label(metric)
    raise ArgumentError, "métrica desconhecida: #{metric.inspect}" unless METRICS.include?(metric)

    I18n.t("progress.metrics.#{metric}.label", locale: :'pt-BR', raise: true)
  end

  # Envelope do ponderado §2.1: `{ value, metric: "weighted", label }`.
  def self.weighted(value)
    { value: value.to_i, metric: WEIGHTED, label: label(WEIGHTED) }
  end

  # Envelope da contagem crua §3.2: `{ completed, total, percent, metric, label }`.
  def self.raw_completion(completed:, total:, percent:)
    {
      completed: completed.to_i, total: total.to_i, percent: percent.to_i,
      metric: RAW_COUNT, label: label(RAW_COUNT)
    }
  end
end
