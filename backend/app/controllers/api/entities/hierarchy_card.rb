# frozen_string_literal: true

module Api
  module Entities
    # hierarchy-screens 1.2 (D-A / D15) — o CARD de qualquer nível (projeto, célula
    # ou robô). O CONTRATO que torna a unificação das métricas impossível de cometer
    # sem quebrar um teste: expõe SEMPRE `weighted_progress` (o envelope §2.1, que o
    # anel consome) e NUNCA um campo chamado `progress`. Os campos de badge do nível
    # (contagem de filhos, ou a Aplicação do robô) saem só quando o service os
    # fornece. Recebe um Hash montado pelo service agregador.
    class HierarchyCard < Grape::Entity
      expose(:id) { |o, _| o[:id] }
      expose(:name) { |o, _| o[:name] }

      # O anel é SEMPRE o ponderado, no envelope rotulado (D14) — nunca um `progress`
      # solto que o front possa confundir com a contagem crua.
      expose(:weighted_progress) { |o, _| ProgressMetric.weighted(o[:weighted_progress]) }

      # Badge do card, por nível — cada service preenche só o seu:
      #   projeto → cells_count · célula → robots_count · robô → application
      expose(:cells_count, if: ->(o, _) { o.key?(:cells_count) }) { |o, _| o[:cells_count] }
      expose(:robots_count, if: ->(o, _) { o.key?(:robots_count) }) { |o, _| o[:robots_count] }
      expose(:application, if: ->(o, _) { o.key?(:application) }) { |o, _| o[:application] }

      # Rodapé do card do robô ("N tarefas"); ausente nos demais níveis.
      expose(:tasks_count, if: ->(o, _) { o.key?(:tasks_count) }) { |o, _| o[:tasks_count] }
    end
  end
end
