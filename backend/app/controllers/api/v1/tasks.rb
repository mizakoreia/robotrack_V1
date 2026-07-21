# frozen_string_literal: true

module Api
  module V1
    # robot-tasks 3.1–3.6 (§3.5, §1.4, D-RT-3, D-RT-7, D-RT-8) — leitura e CRUD de
    # tarefa avulsa.
    #
    # Leitura por robô sob `GET /robots/:robot_id/tasks`; escrita avulsa sob
    # `POST /robots/:robot_id/tasks`, `PATCH /tasks/:id`, `DELETE /tasks/:id`.
    # Toda ação declara `TaskPolicy` — `view` recebe 403 nas mutações. Recurso de
    # outro workspace é linha invisível pela RLS → 404 UNIFORME, mesmo corpo de um
    # id inexistente (D-RT-8).
    #
    # `PATCH` rejeita com 422 QUALQUER payload com `progress` ou `status` (D-RT-3):
    # a requisição inteira falha, não grava "só a `desc` permitida". A máquina de
    # estados §2.2 é de `progress-advances`.
    class Tasks < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      helpers do
        def task_result(result)
          unless result[:success]
            error!({ error: result[:error], details: result[:details] }.compact, result[:status])
          end
          status result[:status]
          result
        end

        def authorization_context = env['api.authorization_context']

        def not_found! = error!({ error: 'not_found' }, 404)
      end

      resource :robots do
        route_param :robot_id do
          resource :tasks do
            route_setting :policy, policy: 'TaskPolicy', action: :index
            get do
              # Robô invisível (inexistente ou de outro workspace) → 404; robô
              # visível sem tarefas → 200 com [].
              not_found! if ::Robot.find_by(id: params[:robot_id]).nil?
              present ::Tasks::ListService.for_robot(params[:robot_id]).to_a, with: Api::Entities::Task
            end

            route_setting :policy, policy: 'TaskPolicy', action: :create
            params do
              optional :id, type: String
              requires :cat, type: String
              requires :desc, type: String
            end
            post do
              result = task_result(
                ::Tasks::CreateService.new(context: authorization_context)
                  .call(robot_id: params[:robot_id], id: params[:id], cat: params[:cat], desc: params[:desc])
              )
              present result[:data][:record], with: Api::Entities::Task
            end
          end

          # task-catalog 5.4 (§2.6) — sincronização retroativa das tarefas-base.
          # `TaskTemplatePolicy.sync?` → owner/edit (view 403). Resposta camelCase
          # `addedCount` (o que o cliente legado espera).
          route_setting :policy, policy: 'TaskTemplatePolicy', action: :sync
          post 'sync_task_templates' do
            result = task_result(
              ::TaskTemplates::SyncToRobotService.new(context: authorization_context)
                .call(robot_id: params[:robot_id])
            )
            { addedCount: result[:data][:added_count] }
          end
        end
      end

      resource :tasks do
        route_param :id do
          route_setting :policy, policy: 'TaskPolicy', action: :update
          params do
            requires :lock_version, type: Integer
            optional :desc, type: String
          end
          patch do
            # D-RT-3: campos read-only nesta capacidade. A requisição INTEIRA
            # falha 422 — não grava a `desc` "só a parte permitida".
            proibidos = %w[progress status].select { |campo| params.key?(campo) }
            error!({ error: 'read_only_field', details: { rejected: proibidos } }, 422) if proibidos.any?

            result = task_result(
              ::Tasks::UpdateService.new(context: authorization_context)
                .call(id: params[:id], desc: params[:desc], lock_version: params[:lock_version])
            )
            present result[:data][:record], with: Api::Entities::Task
          end

          route_setting :policy, policy: 'TaskPolicy', action: :destroy
          delete do
            task_result(::Tasks::DeleteService.new(context: authorization_context).call(id: params[:id]))
            body false
          end

          # robot-tasks 4.2 — PUT idempotente do CONJUNTO de responsáveis.
          # `person_ids: []` (ou ausente) zera; `assign?` → owner/edit (view 403).
          resource :assignees do
            route_setting :policy, policy: 'TaskPolicy', action: :assign
            params do
              optional :person_ids, type: Array[String], default: []
            end
            put do
              result = task_result(
                ::Tasks::AssigneesService.new(context: authorization_context)
                  .replace(task_id: params[:id], person_ids: params[:person_ids])
              )
              result[:data] # { added: [...], removed: [...] }
            end
          end
        end
      end
    end
  end
end
