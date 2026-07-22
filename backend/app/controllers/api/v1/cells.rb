# frozen_string_literal: true

module Api
  module V1
    # commissioning-hierarchy 4.5 — CRUD de células (§1.1, §3.3). Superfície
    # PLANA (`/cells?project_id=`): o pai vai por parâmetro e é validado sob
    # RLS pela service — projeto de outro workspace = 404, não 403.
    class Cells < Grape::API
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

      resource :cells do
        route_setting :policy, policy: 'CellPolicy', action: :index
        params do
          requires :project_id, type: String
        end
        get do
          error!({ error: 'not_found' }, 404) if ::Project.find_by(id: params[:project_id]).nil?
          present ::Cell.where(project_id: params[:project_id]).order(:position).to_a,
                  with: Api::Entities::Cell
        end

        # hierarchy-screens 2.3 (§3.4) — a Visão da CÉLULA. Antes de `patch ':id'`.
        # 404 byte-idêntico para célula ausente E cross-tenant (RLS oculta).
        route_setting :policy, policy: 'CellPolicy', action: :show
        get ':id/overview' do
          cell = ::Cell.find_by(id: params[:id])
          error!({ error: 'not_found' }, 404) if cell.nil?
          ::Hierarchy::CellOverviewService.call(cell: cell)
        end

        route_setting :policy, policy: 'CellPolicy', action: :create
        params do
          optional :id, type: String
          requires :name, type: String
          requires :project_id, type: String
        end
        post do
          result = hierarchy_result(
            ::Hierarchy::CellsService.new(context: authorization_context)
              .create(id: params[:id], name: params[:name], parent_id: params[:project_id])
          )
          present result[:data][:record], with: Api::Entities::Cell
        end

        # §2.9 — reorder em lote; escopo = projeto. Antes de `patch ':id'`.
        route_setting :policy, policy: 'CellPolicy', action: :reorder
        params do
          requires :scope_id, type: String
          requires :ordered_ids, type: Array[String]
        end
        patch 'reorder' do
          result = hierarchy_result(
            ::Hierarchy::ReorderService.new(model: ::Cell)
              .call(scope_id: params[:scope_id], ordered_ids: params[:ordered_ids])
          )
          present result[:data][:records], with: Api::Entities::Cell
        end

        route_setting :policy, policy: 'CellPolicy', action: :update
        params do
          requires :id, type: String
          optional :name, type: String
          requires :lock_version, type: Integer
        end
        patch ':id' do
          result = hierarchy_result(
            ::Hierarchy::CellsService.new(context: authorization_context)
              .update(id: params[:id], name: params[:name], lock_version: params[:lock_version])
          )
          present result[:data][:record], with: Api::Entities::Cell
        end

        route_setting :policy, policy: 'CellPolicy', action: :destroy
        params do
          requires :id, type: String
        end
        delete ':id' do
          hierarchy_result(
            ::Hierarchy::CellsService.new(context: authorization_context).destroy(id: params[:id])
          )
          body false
        end
      end
    end
  end
end
