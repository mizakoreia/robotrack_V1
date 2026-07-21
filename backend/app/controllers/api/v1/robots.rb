# frozen_string_literal: true

module Api
  module V1
    # commissioning-hierarchy 4.5 — CRUD de robôs (§1.1, §1.2, §3.4).
    class Robots < Grape::API
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

      resource :robots do
        route_setting :policy, policy: 'RobotPolicy', action: :index
        params do
          requires :cell_id, type: String
        end
        get do
          error!({ error: 'not_found' }, 404) if ::Cell.find_by(id: params[:cell_id]).nil?
          present ::Robot.where(cell_id: params[:cell_id]).order(:position).to_a,
                  with: Api::Entities::Robot
        end

        route_setting :policy, policy: 'RobotPolicy', action: :create
        params do
          optional :id, type: String
          requires :name, type: String
          requires :cell_id, type: String
          optional :application, type: String
        end
        post do
          result = hierarchy_result(
            ::Hierarchy::RobotsService.new(context: authorization_context)
              .create(id: params[:id], name: params[:name], parent_id: params[:cell_id],
                      extra: { application: params[:application] })
          )
          present result[:data][:record], with: Api::Entities::Robot
        end

        route_setting :policy, policy: 'RobotPolicy', action: :update
        params do
          requires :id, type: String
          optional :name, type: String
          optional :application, type: String
          requires :lock_version, type: Integer
        end
        patch ':id' do
          extra = {}
          if params.key?(:application)
            unless ::Robot::APPLICATIONS.include?(params[:application])
              error!({ error: 'invalid_application', details: { allowed: ::Robot::APPLICATIONS } }, 422)
            end
            extra[:application] = params[:application]
          end

          result = hierarchy_result(
            ::Hierarchy::RobotsService.new(context: authorization_context)
              .update(id: params[:id], name: params[:name], lock_version: params[:lock_version], extra: extra)
          )
          present result[:data][:record], with: Api::Entities::Robot
        end

        route_setting :policy, policy: 'RobotPolicy', action: :destroy
        params do
          requires :id, type: String
        end
        delete ':id' do
          hierarchy_result(
            ::Hierarchy::RobotsService.new(context: authorization_context).destroy(id: params[:id])
          )
          body false
        end
      end
    end
  end
end
