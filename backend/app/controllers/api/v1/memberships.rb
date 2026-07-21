# frozen_string_literal: true

module Api
  module V1
    # team-access-management §"Painel de equipe" (tarefa 4.4).
    #
    # As três rotas são de DOMÍNIO: exigem `X-Workspace-Id`, passam pela
    # resolução de papel no servidor e caem na varredura de tenant. Cada uma
    # declara a policy que decide (`route_setting :policy`), e a varredura de
    # policies reprova qualquer rota nova de convite/equipe que esqueça de fazê-lo.
    class Memberships < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :memberships do
        # GET /api/v1/memberships — membros do workspace corrente (qualquer
        # membro lê; só o dono muta).
        route_setting :policy, policy: 'MembershipPolicy', action: :index
        get do
          result = ::Memberships::ListService.new(
            current_user: env['api.current_user'],
            current_role: env['api.current_role'],
            workspace_id: env['api.current_workspace_id']
          ).call
          error!({ error: result[:error] }, result[:status]) unless result[:success]

          # authorization-policies 4.4: a contagem também é escopada pelo tenant
          # — vazamento por header é vazamento igual.
          header 'X-Total-Count', result[:data][:members].size.to_s
          present result[:data][:members], with: Api::Entities::Membership
        end

        # PATCH /api/v1/memberships/:id — só o dono, só entre view e edit.
        route_setting :policy, policy: 'MembershipPolicy', action: :update
        params do
          requires :id, type: String
          requires :role, type: String
        end
        patch ':id' do
          result = ::Memberships::UpdateRoleService.new(
            current_user: env['api.current_user'],
            current_role: env['api.current_role'],
            workspace_id: env['api.current_workspace_id'],
            membership_id: params[:id],
            role: params[:role]
          ).call
          error!({ error: result[:error] }, result[:status]) unless result[:success]

          status 200
          result[:data]
        end

        # DELETE /api/v1/memberships/:id — só o dono; nunca o próprio dono.
        route_setting :policy, policy: 'MembershipPolicy', action: :destroy
        params do
          requires :id, type: String
        end
        delete ':id' do
          result = ::Memberships::RemoveService.new(
            current_user: env['api.current_user'],
            current_role: env['api.current_role'],
            workspace_id: env['api.current_workspace_id'],
            membership_id: params[:id]
          ).call
          error!({ error: result[:error] }, result[:status]) unless result[:success]

          status 204
          body false
        end
      end
    end
  end
end
