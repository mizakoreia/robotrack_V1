# frozen_string_literal: true

module Api
  module V1
    # robot-tasks 5.5 (§2.5, D-RT-4, D-RT-8) — criação de robôs em lote.
    #
    # A UI é de dois passos, mas a chamada é UMA requisição
    # `POST /cells/:cell_id/robots/batch` com `{application, robots: [{id, name}]}`.
    # `RobotBatchPolicy` (owner/edit; view 403). Célula de outro workspace é linha
    # invisível pela RLS → 404, sem revelar o nome da célula.
    class RobotBatches < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      helpers do
        def authorization_context = env['api.authorization_context']
      end

      resource :cells do
        route_param :cell_id do
          route_setting :policy, policy: 'RobotBatchPolicy', action: :create
          params do
            requires :application, type: String
            requires :robots, type: Array do
              optional :id, type: String
              optional :name, type: String
            end
          end
          post 'robots/batch' do
            result = ::Robots::BatchCreateService.new(context: authorization_context).call(
              cell_id: params[:cell_id], application: params[:application], robots: params[:robots]
            )
            unless result[:success]
              error!({ error: result[:error], details: result[:details] }.compact, result[:status])
            end
            status result[:status]
            result[:data]
          end
        end
      end
    end
  end
end
