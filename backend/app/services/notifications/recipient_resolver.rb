# frozen_string_literal: true

module Notifications
  # Resolve QUEM recebe (in-app-notifications 3.1 / §2.7). Duas fontes de conjunto
  # bruto por tipo, seguidas de dedup e subtração do autor, NESSA ORDEM:
  #   :assign            → delta (novos_assignees − assignees_anteriores)
  #   :progress/:done    → todos os responsáveis atuais
  # depois: uniq por person_id, e subtrai actor_person_id (nunca o autor —
  # inclusive na autoatribuição, §2.3). Autor único responsável → conjunto VAZIO.
  module RecipientResolver
    module_function

    def resolve(type:, actor_person_id:, current_assignees:, previous_assignees: [])
      raw =
        case type.to_sym
        when :assign then current_assignees - previous_assignees
        else current_assignees
        end

      raw.uniq.reject { |person_id| person_id == actor_person_id }
    end
  end
end
