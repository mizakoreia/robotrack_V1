# frozen_string_literal: true

module Api
  module V1
    # commissioning-report 1.3 (§3.8, §4.1) — o endpoint do Protocolo de
    # Comissionamento. Rota de DOMÍNIO: exige `X-Workspace-Id`; o gate resolve o
    # tenant e avalia `ReportPolicy` (membership em qualquer papel) ANTES daqui.
    #
    # `scope=all` (workspace, via RLS) | `scope=project&project_id=<uuid>`; qualquer
    # outro valor de scope → 400. Projeto invisível (inexistente/cross-tenant) →
    # 404. Leitura pura, sem parâmetro de identidade — o gerador vem do token.
    class Reports < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :commissioning_report do
        route_setting :policy, policy: 'ReportPolicy', action: :show
        params do
          optional :scope, type: String, default: 'all'
          optional :project_id, type: String
        end
        get do
          result = ::Reports::CommissioningReportService
                   .new(context: env['api.authorization_context'])
                   .call(scope: params[:scope], project_id: params[:project_id],
                         time_zone: report_time_zone)

          unless result[:success]
            error!({ error: result[:error] }, result[:status])
          end
          present result[:data], with: Api::Entities::CommissioningReport
        end
      end

      helpers do
        # workspace-tenancy ainda não expõe `time_zone` — default `America/Sao_Paulo`
        # (D-R6). Quando expuser, basta ler do workspace aqui.
        def report_time_zone
          ::Reports::DocumentId::DEFAULT_TIME_ZONE
        end
      end
    end
  end
end
