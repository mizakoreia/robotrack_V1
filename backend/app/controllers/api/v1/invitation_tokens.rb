# frozen_string_literal: true

module Api
  module V1
    # workspace-invitations §"Pré-visualização pública" e §"Consumo atômico"
    # (tarefas 3.3, 3.4).
    #
    # As DUAS rotas por token vivem fora do mundo de tenant, e isso é deliberado:
    # o convidado ainda não é membro de workspace nenhum, então exigir
    # `X-Workspace-Id` tornaria o aceite impossível. A isenção é DECLARADA em
    # `Api::Root::TENANT_EXEMPT_ROUTES` (ciente de método, para não arrastar
    # junto o `DELETE /api/v1/invitations/:id`, que é rota de domínio normal).
    #
    # Nenhuma das duas declara policy: não há papel a consultar: a pré-visualização
    # é pública por desenho e a autorização do aceite É a invariante 6, avaliada
    # dentro da transação com a linha travada.
    class InvitationTokens < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :invitations do
        # GET /api/v1/invitations/:token — público (pré-login).
        params do
          requires :token, type: String
        end
        get ':token' do
          result = ::Invitations::PreviewService.new(token: params[:token]).call
          error!({ error: result[:error] }, result[:status]) unless result[:success]

          present result[:data], with: Api::Entities::InvitationPreview
        end

        # POST /api/v1/invitations/:token/accept — autenticado, sem tenant.
        params do
          requires :token, type: String
        end
        post ':token/accept' do
          result = ::Invitations::AcceptService.new(
            current_user: env['api.current_user'],
            token: params[:token],
            requested_workspace_id: headers['X-Workspace-Id'] || headers['HTTP_X_WORKSPACE_ID'],
            extra_params: request.params
          ).call

          error!({ error: result[:error] }, result[:status]) unless result[:success]

          status 200
          result[:data]
        end
      end
    end
  end
end
