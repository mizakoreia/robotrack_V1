# frozen_string_literal: true

module Api
  module V1
    class Permissions < Grape::API
      helpers Api::V1::ControllerHelpers
      resource :me do
        desc 'Minhas permissões' do
          summary 'Lista permissões do usuário atual'
          success [{ code: 200, message: 'Ok', model: Api::Entities::UserPermission }]
        end
        get '' do
          error!({ error: 'unauthorized' }, 401) unless defined?(@current_user) && @current_user
          ups = UserPermission.where(user_id: @current_user.id).includes(:permission)
          present Api::Entities::UserPermission.represent(ups)
        end
      end

      resource :sync do
        desc 'Sincronizar permissões' do
          summary 'Dispara sincronização por usuário ou plano'
        end
        params do
          optional :user_id, type: String
          optional :plan_id, type: Integer
        end
        post '' do
          if params[:user_id].present?
            user = User.find_by(id: params[:user_id])
            result = PermissionsSyncService.sync_for_user(user)
            process_service_response(result)
          elsif params[:plan_id].present?
            plan = Plan.find_by(id: params[:plan_id])
            result = PermissionsSyncService.sync_for_plan(plan)
            process_service_response(result)
          else
            error!({ error: 'validation_error', message: 'Informe user_id ou plan_id' }, 400)
          end
        end
      end
    end
  end
end
