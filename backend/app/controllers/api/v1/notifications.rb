# frozen_string_literal: true

module Api
  module V1
    # in-app-notifications 5.1/5.2 — o centro de notificações. Rota de DOMÍNIO
    # (X-Workspace-Id, RLS). A superfície é MÍNIMA e não tem PATCH genérico: só
    # listagem, marcar UMA como lida e marcar TODAS. A inv. 4 (só read/read_at
    # mudam) é reforçada no banco; aqui a superfície de escrita simplesmente não
    # existe (o route-sweep prova).
    #
    # Escopo: `recipient_person_id = pessoa corrente` — Ana nunca vê as de Bruno,
    # nem no mesmo workspace. A marcação exige `recipient == current` (a PRÓPRIA):
    # nem o dono marca a de outra pessoa (NotificationPolicy).
    class Notifications < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      MAX_PER_PAGE = 50

      helpers do
        def current_person_id
          ::Current.actor_person_id
        end

        def auth_context
          env['api.authorization_context']
        end
      end

      resource :notifications do
        route_setting :policy, policy: 'NotificationPolicy', action: :index
        params do
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: MAX_PER_PAGE
        end
        get do
          per = params[:per_page].to_i.clamp(1, MAX_PER_PAGE)
          page = [params[:page].to_i, 1].max
          scope = ::Notification.where(recipient_person_id: current_person_id).order(recorded_at: :desc)

          header 'X-Unread-Count', scope.where(read: false).count.to_s
          present scope.limit(per).offset((page - 1) * per), with: Api::Entities::Notification
        end

        route_setting :policy, policy: 'NotificationPolicy', action: :mark_read
        post 'read_all' do
          ::Notification.where(recipient_person_id: current_person_id, read: false)
                        .update_all(read: true, read_at: Time.current)
          status 200
          { ok: true }
        end

        route_param :id, type: String do
          route_setting :policy, policy: 'NotificationPolicy', action: :mark_read
          post :read do
            notification = ::Notification.find_by(id: params[:id]) # RLS já escopa por workspace
            error!({ error: 'not_found' }, 404) if notification.nil?

            # A PRÓPRIA (inv. 4): nem o dono marca a de outra pessoa. Sem vazar a
            # existência do id de outro tenant (RLS já devolveu nil → 404 acima).
            unless ::NotificationPolicy.mark_read?(auth_context, notification)
              error!({ error: 'forbidden' }, 403)
            end

            notification.update!(read: true, read_at: Time.current)
            status 200
            present notification, with: Api::Entities::Notification
          end
        end
      end
    end
  end
end
