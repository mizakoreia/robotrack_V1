# frozen_string_literal: true

module Api
  module V1
    # progress-rollup 4.5 — recálculo MANUAL do cache do workspace corrente. É a
    # válvula para depois de uma correção de dado ou de um bug de cascata já
    # corrigido: recomputa em massa (3 statements) sob a RLS do tenant da sessão.
    #
    # `ProgressPolicy.recompute?` = owner/edit; `view` → 403. Classe nomeada
    # `ProgressEndpoint` (não `Progress`) para não sombrear o módulo de serviços
    # `::Progress` dentro do próprio corpo.
    class ProgressEndpoint < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :progress do
        route_setting :policy, policy: 'ProgressPolicy', action: :recompute
        post 'recompute' do
          ::Progress::BulkRecompute.call(workspace_id: env['api.current_workspace_id'])
          status 200 # recálculo não cria recurso
          { recomputed: true }
        end
      end
    end
  end
end
