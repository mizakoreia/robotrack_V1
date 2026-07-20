# Endpoint Grape para Analytics do Dashboard
# Consolida dados de vendas, assinaturas e leads em um único payload,
# oferecendo também exportações CSV/PDF.
module Api
  module V1
    class Analytics < Grape::API
      helpers Api::V1::ControllerHelpers

      desc 'Dashboard Analytics Unificado' do
        summary 'Retorna dados agregados para gráficos, tabelas e KPIs'
        detail 'Consolida vendas, assinaturas e leads em um único payload para o dashboard.'
        success [code: 200, message: 'Ok']
      end

      params do
        optional :period, type: String, values: %w[day week month quarter year], default: 'month'
        optional :date_from, type: String
        optional :date_to, type: String
        optional :region, type: String
        optional :product_type, type: String
        optional :page, type: Integer, default: 1
        optional :per_page, type: Integer, default: 20
        optional :sort_by, type: String, default: 'volume'
        optional :sort_dir, type: String, values: %w[asc desc], default: 'desc'
      end

      get 'dashboard', http_codes: [[200, 'OK'], [422, 'Erro de validação']] do
        result = AnalyticsService.dashboard(params)
        process_service_response(result)
      end

      desc 'Exportar relatório CSV do dashboard' do
        summary 'Gera CSV com dados agregados conforme filtros'
        detail 'Exporta um CSV com tabelas e métricas do dashboard.'
        success [code: 200, message: 'Ok']
      end
      get 'dashboard/report.csv', http_codes: [[200, 'OK']] do
        result = AnalyticsService.report_csv(params)
        process_service_response(result)
      end

      desc 'Exportar relatório PDF do dashboard' do
        summary 'Gera PDF com dados agregados conforme filtros'
        detail 'Exporta um PDF com visões resumidas do dashboard.'
        success [code: 200, message: 'Ok']
      end
      get 'dashboard/report.pdf', http_codes: [[200, 'OK']] do
        result = AnalyticsService.report_pdf(params)
        process_service_response(result)
      end
    end
  end
end
