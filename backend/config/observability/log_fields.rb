# frozen_string_literal: true

module Observability
  # Campos do log estruturado (delivery-and-observability 4.3). Extraídos do payload
  # do evento de request + do contexto `Current` (setado no before-hook do Grape).
  # Uma requisição pública sem usuário emite `user_id: nil` sem exceção — nunca
  # levanta na formatação.
  module LogFields
    module_function

    def custom(event_payload = {}, current: default_current)
      {
        request_id: current[:request_id],
        user_id: current[:user_id],
        workspace_id: current[:workspace_id],
        person_id: current[:actor_person_id],
        policy: event_payload[:policy],
        db_runtime: event_payload[:db_runtime]&.round(1)
      }.compact
    end

    def default_current
      c = defined?(Current) ? Current : nil
      {
        request_id: c&.respond_to?(:request_id) ? c.request_id : nil,
        user_id: c&.respond_to?(:user_id) ? c.user_id : nil,
        workspace_id: c&.respond_to?(:workspace_id) ? c.workspace_id : nil,
        actor_person_id: c&.respond_to?(:actor_person_id) ? c.actor_person_id : nil
      }
    end
  end
end
