# frozen_string_literal: true

module Api
  module V1
    # notification-preferences D-P6 — preferência PESSOAL de notificação por entidade
    # (seguir/silenciar projeto/célula/robô). Rota de DOMÍNIO (X-Workspace-Id, RLS).
    #
    # A escrita é SEMPRE para a pessoa corrente: o endpoint NÃO aceita `person_id` de
    # terceiro, então não há como editar a preferência alheia (D-P6). `state`:
    # `follow`/`mute` fazem upsert (índice único parcial garante uma linha por alvo);
    # `default` APAGA a linha (volta ao comportamento padrão). Não existe superfície
    # para escrever a preferência de outra pessoa nem para tocar outra coluna.
    class NotificationSubscriptions < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      SCOPE_COLUMN = { 'project' => :scope_project_id, 'cell' => :scope_cell_id, 'robot' => :scope_robot_id }.freeze

      helpers do
        def current_person_id
          ::Current.actor_person_id
        end
      end

      resource :notification_subscriptions do
        route_setting :policy, policy: 'NotificationSubscriptionPolicy', action: :index
        get do
          scope = ::NotificationSubscription.where(person_id: current_person_id).order(created_at: :asc)
          present scope, with: Api::Entities::NotificationSubscription
        end

        route_setting :policy, policy: 'NotificationSubscriptionPolicy', action: :mutate
        params do
          requires :scope_type, type: String, values: %w[project cell robot]
          requires :scope_id, type: String
          requires :state, type: String, values: %w[follow mute default]
        end
        put do
          column = SCOPE_COLUMN.fetch(params[:scope_type])
          existing = ::NotificationSubscription.find_by(person_id: current_person_id, column => params[:scope_id])

          if params[:state] == 'default'
            existing&.destroy!
            status 200
            next({ ok: true, state: 'default' })
          end

          record = existing || ::NotificationSubscription.new(person_id: current_person_id, column => params[:scope_id])
          record.state = params[:state]
          record.save!
          status 200
          present record, with: Api::Entities::NotificationSubscription
        rescue ActiveRecord::RecordInvalid => e
          error!({ error: 'invalid', detail: e.record.errors.full_messages }, 422)
        end
      end
    end
  end
end
