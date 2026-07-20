# frozen_string_literal: true

module Api
  module V1
    # Endpoint de DOMÍNIO montado APENAS em teste (api/v1/base.rb). Existe para
    # exercitar a fiação de tenant do request HTTP (resolução no `before`,
    # transação do middleware) enquanto nenhuma capacidade de domínio real tem
    # rota — e para a varredura de rotas de tenant (4.6) não ser vacuamente verde.
    #
    # Por estar FORA de Api::Root::TENANT_EXEMPT_ROUTES, toda chamada aqui passa
    # pela resolução de tenant: sem `X-Workspace-Id` responde 400.
    class TenancyProbe < Grape::API
      format :json

      namespace :tenancy_probe do
        # Devolve o contexto resolvido e o que o banco enxerga de fato.
        desc 'Sonda de contexto de tenant (só teste)', hidden: true
        get :context do
          {
            workspace_id: env['api.current_workspace_id'],
            role: env['api.current_role'],
            db_workspace_id: ActiveRecord::Base.connection.select_value(
              "SELECT current_setting('app.current_workspace_id', true)"
            ).presence,
            people_count: Person.count
          }
        end

        # Levanta exceção DEPOIS de o contexto estar aberto — para provar que o
        # ROLLBACK descarta o SET LOCAL e a request seguinte não vaza (4.5).
        desc 'Sonda que levanta exceção (só teste)', hidden: true
        get :boom do
          Person.count # toca o banco com contexto aberto
          raise 'boom proposital'
        end
      end
    end
  end
end
