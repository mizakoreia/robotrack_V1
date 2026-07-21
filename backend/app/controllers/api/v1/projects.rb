# frozen_string_literal: true

module Api
  module V1
    # commissioning-hierarchy 4.5 — CRUD de projetos (§1.1, §3.3).
    #
    # Rotas de DOMÍNIO: exigem `X-Workspace-Id`, o gate resolve o contexto e
    # avalia a policy declarada ANTES de qualquer service (invariante 1).
    # `workspace_id` NÃO é param de nenhuma rota — o tenant vem da sessão,
    # nunca do corpo (D2; o WITH CHECK da RLS é o backstop).
    class Projects < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      helpers do
        def hierarchy_result(result)
          unless result[:success]
            error!({ error: result[:error], details: result[:details] }.compact, result[:status])
          end
          status result[:status]
          result
        end

        def authorization_context = env['api.authorization_context']
      end

      resource :projects do
        route_setting :policy, policy: 'ProjectPolicy', action: :index
        get do
          present ::Project.order(:position).to_a, with: Api::Entities::Project
        end

        route_setting :policy, policy: 'ProjectPolicy', action: :create
        params do
          optional :id, type: String
          requires :name, type: String
        end
        post do
          result = hierarchy_result(
            ::Hierarchy::ProjectsService.new(context: authorization_context)
              .create(id: params[:id], name: params[:name])
          )
          present result[:data][:record], with: Api::Entities::Project
        end

        route_setting :policy, policy: 'ProjectPolicy', action: :update
        params do
          requires :id, type: String
          optional :name, type: String
          requires :lock_version, type: Integer
        end
        patch ':id' do
          result = hierarchy_result(
            ::Hierarchy::ProjectsService.new(context: authorization_context)
              .update(id: params[:id], name: params[:name], lock_version: params[:lock_version])
          )
          present result[:data][:record], with: Api::Entities::Project
        end

        route_setting :policy, policy: 'ProjectPolicy', action: :destroy
        params do
          requires :id, type: String
        end
        delete ':id' do
          hierarchy_result(
            ::Hierarchy::ProjectsService.new(context: authorization_context).destroy(id: params[:id])
          )
          body false
        end
      end
    end
  end
end
