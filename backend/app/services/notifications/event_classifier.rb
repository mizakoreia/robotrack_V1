# frozen_string_literal: true

module Notifications
  # Classifica o avanço em tipo de notificação (in-app-notifications 3.2 / §2.7).
  # Função PURA de (from, to):
  #   to == 100        → :done   (nunca :progress)
  #   0 < to < 100     → :progress
  #   to == 0          → nil     (reset — zero notificação)
  module EventClassifier
    module_function

    def classify(from:, to:)
      return :done if to == 100
      return :progress if to.positive? && to < 100

      nil
    end
  end
end
