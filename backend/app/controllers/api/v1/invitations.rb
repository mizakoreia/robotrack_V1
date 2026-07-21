# frozen_string_literal: true

module Api
  module V1
    # workspace-invitations §"Criação de convite" e §"Revogação" (tarefa 2.4).
    #
    # Superfície de DOMÍNIO: as três rotas abaixo exigem `X-Workspace-Id` e caem
    # na varredura de tenant. Os dois caminhos POR TOKEN (pré-visualização
    # pública e aceite) são outra coisa — acontecem fora de um workspace corrente
    # e vivem em `Api::V1::InvitationTokens`.
    #
    # `route_setting :policy` declara, na própria rota, qual policy decide. É o
    # gancho que o route-sweep lê para reprovar um endpoint novo que esqueça de
    # se declarar (invariante 1) — e a forma que `authorization-policies` vai
    # generalizar.
    class Invitations < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :invitations do
        # GET /api/v1/invitations — convites do workspace corrente (só o dono).
        route_setting :policy, 'InvitationPolicy#index?'
        get do
          policy = InvitationPolicy.new(role: env['api.current_role'],
                                        user: env['api.current_user'],
                                        workspace_id: env['api.current_workspace_id'])
          error!({ error: 'forbidden' }, 403) unless policy.index?

          present ::Invitation.order(created_at: :desc).to_a, with: Api::Entities::Invitation
        end

        # POST /api/v1/invitations — cria e devolve o link absoluto.
        route_setting :policy, 'InvitationPolicy#create?'
        params do
          requires :email, type: String
          requires :role, type: String
          optional :workspace_id, type: String
        end
        post do
          result = ::Invitations::CreateService.new(
            current_user: env['api.current_user'],
            current_role: env['api.current_role'],
            workspace_id: env['api.current_workspace_id'],
            email: params[:email],
            role: params[:role],
            requested_workspace_id: params[:workspace_id]
          ).call

          error!({ error: result[:error] }, result[:status]) unless result[:success]

          status 201
          present result[:data][:invitation], with: Api::Entities::Invitation
        end

        # DELETE /api/v1/invitations/:id — revogação (só o dono, só pendente).
        route_setting :policy, 'InvitationPolicy#destroy?'
        params do
          requires :id, type: String
        end
        delete ':id' do
          result = ::Invitations::RevokeService.new(
            current_user: env['api.current_user'],
            current_role: env['api.current_role'],
            workspace_id: env['api.current_workspace_id'],
            invitation_id: params[:id]
          ).call

          error!({ error: result[:error] }, result[:status]) unless result[:success]

          status 204
          body false
        end
      end
    end
  end
end
