# frozen_string_literal: true

module Api
  module V1
    # my-tasks-view 3.1/3.3/3.4 (§3.6, D-MTV-2/4/10) — o endpoint de "Minhas
    # Tarefas". Rota de DOMÍNIO: exige `X-Workspace-Id`; o gate resolve o tenant e
    # avalia `MyTasksPolicy` (membership em qualquer papel) ANTES daqui.
    #
    # O viewer é a `Person` do token NESTE workspace, resolvida pelo
    # `authorization_context` (= `Person.find_by(workspace_id:, user_id:)`). Se ela
    # NÃO existir para um membro (dado legado escrito antes da constraint
    # `memberships.person_id NOT NULL`), respondemos **409 person_missing** — NUNCA
    # `200 []` (D-MTV-2: uma lista vazia é indistinguível de "não tenho tarefas", e
    # é essa falha silenciosa que a capacidade existe para matar).
    #
    # `person_id` NÃO é parâmetro (D-MTV-10): mesmo enviado, é ignorado — o viewer
    # vem só do token. Escopo de tenant é a RLS (o service filtra `workspace_id`
    # ALÉM dela, por ser prefixo do índice).
    class MyTasks < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :my_tasks do
        route_setting :policy, policy: 'MyTasksPolicy', action: :index
        params do
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 50
        end
        get do
          person = env['api.authorization_context']&.person
          error!({ error: 'person_missing' }, 409) if person.nil?

          result = ::MyTasks::ListService.new.call(
            workspace_id: env['api.current_workspace_id'],
            person_id: person.id,
            page: params[:page],
            per_page: params[:per_page]
          )
          data = result[:data]
          set_pagination_headers(data[:total], data[:page], data[:per_page])
          present data[:rows], with: Api::Entities::MyTaskRow
        end
      end
    end
  end
end
