# frozen_string_literal: true

require 'ostruct'

module Api
  module V1
    # workspace-core §"Índice do usuário" e §"Imutabilidade do dono" (tarefas 6.1, 6.2).
    #
    # Rota SEM tenant específico (consta de Api::Root::TENANT_EXEMPT_ROUTES): é
    # onde o usuário descobre seus workspaces ANTES de escolher um. O índice é
    # derivado AO VIVO de `workspaces` + `memberships` — não há tabela
    # materializada (D9). O papel devolvido é rótulo; toda decisão resolve o papel
    # de novo no servidor.
    class Workspaces < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :workspaces do
        # GET /api/v1/workspaces — os workspaces em que o usuário é dono ou membro.
        get do
          user = env['api.current_user']
          items = ActiveRecord::Base.transaction do
            Tenant.set_user!(user.id)
            list_for(user)
          end
          present items, with: Api::Entities::Workspace
        end

        # PATCH /api/v1/workspaces/:id — só o dono, e só o `name`.
        params do
          requires :id, type: String
          optional :name, type: String
        end
        patch ':id' do
          user = env['api.current_user']
          ws_id = params[:id]

          resolution = ActiveRecord::Base.transaction do
            ::Workspaces::ResolveCurrentService.new(user: user, workspace_id: ws_id).call
          end
          error!({ error: resolution.error }, resolution.status) unless resolution.ok
          error!({ error: 'workspace_access_denied' }, 403) unless resolution.role == :owner

          # Só `name` é mutável. Qualquer outra chave (owner_user_id, id novo...) é 422.
          allowed = %w[id name route_info version format]
          extra = request.params.keys.map(&:to_s) - allowed
          error!({ error: 'unpermitted_parameters', details: extra }, 422) if extra.any?

          updated = Tenant.with(workspace_id: ws_id, user_id: user.id) do
            ws = Workspace.where(id: ws_id).first
            ws.update!(name: params[:name]) if params[:name].present?
            ws
          end

          present OpenStruct.new(id: updated.id, name: updated.name, role: 'owner'),
                  with: Api::Entities::Workspace
        end
      end

      helpers do
        def list_for(user)
          owned = Workspace.where(owner_user_id: user.id).to_a
          member_ids = Membership.where(user_id: user.id).pluck(:workspace_id, :role).to_h
          members = Workspace.where(id: member_ids.keys).to_a

          (owned + members).uniq(&:id).map do |ws|
            role = ws.owner_user_id == user.id ? 'owner' : member_ids[ws.id]
            OpenStruct.new(id: ws.id, name: ws.name, role: role.to_s)
          end
        end
      end
    end
  end
end
