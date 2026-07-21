# frozen_string_literal: true

module Api
  module Entities
    # progress-advances 4.3 (§3.5, D-TS, D8) — uma entrada da trilha como o cliente
    # a lê.
    #
    # `author_name_snapshot` é o nome congelado no instante do avanço (nunca o
    # nome atual da Person — renomear alguém não reescreve a história). `legacy`
    # marca entrada importada. `recorded_at_adjusted` avisa que o `recorded_at`
    # foi clampado (relógio do tablet errado). `synced_late` é derivado: o avanço
    # foi anotado no dispositivo mais de 1h antes de chegar ao servidor — sinal de
    # sincronização tardia/offline, útil para a UI marcar a entrada.
    class TaskAdvance < Grape::Entity
      expose :id
      expose :task_id
      expose :from_progress
      expose :to_progress
      expose :comment
      expose :author_name_snapshot
      expose :legacy
      expose :recorded_at
      expose :created_at
      expose :recorded_at_adjusted
      expose(:synced_late) { |a, _| (a.created_at - a.recorded_at) > 3600 }
    end
  end
end
