# frozen_string_literal: true

module Api
  module V1
    # task-catalog 4.5 (§1.2, D-TC-3) — metadados globais do produto. Hoje só a
    # lista de Aplicações de robô, servida de `Robot::APPLICATIONS` (fonte única
    # no model): 6 valores, na ordem da §1.2, sem a sentinela `"Todas"`. O
    # frontend consome daqui em vez de redeclarar a lista em TS.
    #
    # `access: :authenticated`: exige login, mas não é workspace-scoped — o enum
    # é o mesmo para todo tenant, então a rota é isenta de tenant (ver
    # TENANT_EXEMPT_ROUTES em Api::Root). A autorização fina não se aplica: não
    # há recurso de tenant a proteger.
    class Meta < Grape::API
      format :json

      resource :meta do
        route_setting :policy, access: :authenticated
        get :robot_applications do
          ::Robot::APPLICATIONS
        end
      end
    end
  end
end
