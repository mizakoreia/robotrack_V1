# frozen_string_literal: true

module Api
  module Entities
    # hierarchy-screens 1.2 (D-A / D15) — o HUB analítico de cada tela. Carrega as
    # contagens nomeadas do nível (`counts`) e a CONTAGEM CRUA §3.2 no envelope
    # rotulado (`raw_completion`). O hub NUNCA exibe o ponderado e NUNCA tem um
    # campo `progress`: é o outro lado da divergência do D15. Recebe um Hash do
    # service, com `counts` (inteiros nomeados) e `raw_completion`
    # (`{completed, total, percent}`).
    class AnalyticsHub < Grape::Entity
      expose(:counts) { |o, _| o[:counts] }
      expose(:raw_completion) { |o, _| ProgressMetric.raw_completion(**o[:raw_completion]) }
    end
  end
end
