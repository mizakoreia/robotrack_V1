# frozen_string_literal: true

module Api
  module V1
    # workspace-settings G5 (§3.11, D12, D-RESET-GATE) — `POST /api/v1/workspace/
    # factory_reset`. `owner`-only (`WorkspaceFactoryResetPolicy` = `destroy_workspace`;
    # `edit`/`view` → 403 pelo gate, mesmo com a frase e o backup certos).
    #
    # Atrás de `FEATURE_FACTORY_RESET`: desligada → 404 (esconde a existência da
    # operação; o botão some na UI). A rota DECLARA a policy (senão o gate fail-closed
    # responde 500), então o 404 da flag vem DEPOIS do gate — para o owner, é 404; um
    # não-owner nem chega aqui (403 no gate).
    class WorkspaceFactoryReset < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :workspace do
        resource :factory_reset do
          route_setting :policy, policy: 'WorkspaceFactoryResetPolicy', action: :create
          params do
            requires :confirmation_phrase, type: String
            requires :backup_id, type: String
          end
          post do
            error!({ error: 'not_found' }, 404) unless ::Workspace::FactoryResetService.feature_enabled?

            result = ::Workspace::FactoryResetService.new(context: env['api.authorization_context']).call(
              confirmation_phrase: params[:confirmation_phrase], backup_id: params[:backup_id]
            )
            process_service_response(result)
          end
        end
      end
    end
  end
end
