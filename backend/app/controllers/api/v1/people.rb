# frozen_string_literal: true

module Api
  module V1
    # workspace-settings 2.1/2.2 (§3.9, D10/D-PERSON-DEL) — as pessoas do workspace
    # (responsáveis do chão de fábrica, `user_id` nulo). Rota de DOMÍNIO: header
    # `X-Workspace-Id`, RLS. Listar é `read_workspace`; criar/arquivar é
    # `manage_catalog` (owner/edit — `view` recebe 403).
    #
    # `id` no POST é uuid do cliente (D1) — replay idempotente. Remover é ARQUIVAR
    # (DELETE lógico), nunca físico (People::ArchiveService).
    class People < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :people do
        route_setting :policy, policy: 'WorkspaceSettingsPolicy', action: :index
        get do
          rows = ::Person.where(archived_at: nil).order(Arel.sql('lower(btrim(name))'))
          present rows, with: Api::Entities::Person
        end

        route_setting :policy, policy: 'WorkspaceSettingsPolicy', action: :create
        params do
          optional :id, type: String
          requires :name, type: String
        end
        post do
          person = ::Person.create!(id: params[:id].presence, name: params[:name].to_s.strip)
          present person, with: Api::Entities::Person
        rescue ActiveRecord::RecordNotUnique
          error!({ error: 'name_taken' }, 422)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid
          error!({ error: 'validation_error' }, 422)
        end

        route_setting :policy, policy: 'WorkspaceSettingsPolicy', action: :archive
        delete ':id' do
          result = ::People::ArchiveService.new(context: env['api.authorization_context']).call(person_id: params[:id])
          process_service_response(result)
        end
      end
    end
  end
end
