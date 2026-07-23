# frozen_string_literal: true

module Api
  module V1
    # realtime-collaboration 1.1 / D6.8 — `POST /api/v1/cable_tickets`. Qualquer
    # usuário autenticado troca o Bearer JWT (no header, fora de qualquer log de
    # URL) por um ticket opaco de 60s e uso único, que o cliente leva na query do
    # handshake do Cable (`/cable?ticket=<t>`). Não é rota de DOMÍNIO: o ticket é
    # do usuário, não de um workspace — a autorização de assinatura por membership
    # acontece depois, no `WorkspaceChannel` (grupo 2). Por isso `access:
    # :authenticated` (autenticado basta) e a rota entra em TENANT_EXEMPT_ROUTES.
    class CableTickets < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :cable_tickets do
        route_setting :policy, access: :authenticated
        post do
          ticket = ::Realtime::CableTicketService.issue(env['api.current_user'])
          { ticket:, ttl: ::Realtime::CableTicketService::TTL_SECONDS }
        end
      end
    end
  end
end
