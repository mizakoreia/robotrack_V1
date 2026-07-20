# frozen_string_literal: true

module Api
  module V1
    class Operations < Grape::API
      helpers Api::V1::ControllerHelpers

      resource '' do
        desc 'Listar operações' do
          summary 'Listar operações'
          detail 'Retorna operações com filtros de busca e status.'
          success [code: 200, message: 'Ok', model: Api::Entities::Operation]
          is_array true
        end

        params do
          optional :page, type: Integer, default: 1, desc: 'Página'
          optional :per_page, type: Integer, default: 20, desc: 'Itens por página'
          optional :o, type: Integer, desc: 'Offset'
          optional :l, type: Integer, desc: 'Limit'
          optional :q, type: String, desc: 'Query de busca'
          optional :active, type: Boolean, desc: 'Filtrar por ativo/inativo'
          optional :ordering_keys, type: [String, Array], desc: 'Chaves de ordenação (ex.: ["created_at"])'
          optional :ordering_style, type: [String, Array], desc: 'Estilos de ordenação (ex.: ["down"])'
        end

        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [500, 'Internal Server Error']
        ] do
          result = OperationService.list(params)
          set_pagination_headers(result[:data][:total], params[:page] || 1, params[:per_page] || params[:l] || 20)
          process_service_response(result)
        end

        desc 'Criar operação' do
          summary 'Criar operação'
          detail 'Cria uma nova operação.'
          success [code: 201, message: 'Created', model: Api::Entities::Operation]
        end

        params do
          requires :key, type: String, desc: 'Chave única'
          requires :title, type: String, desc: 'Título'
          optional :description, type: String, desc: 'Descrição'
          optional :keywords, type: [String, Array], desc: 'Palavras‑chave ou regex'
          optional :keywords_string, type: String, desc: 'Palavras‑chave separadas por vírgula'
          optional :active, type: Boolean, desc: 'Status ativo'
        end

        post '', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(OperationService.create(params))
        end
      end

      route_param :id do
        desc 'Detalhe da operação' do
          summary 'Buscar operação por ID'
          success [code: 200, message: 'Ok', model: Api::Entities::Operation]
        end

        params do
          requires :id, type: String, desc: 'ID ou smart_id'
        end

        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(OperationService.get(params[:id]))
        end

        desc 'Excluir operação' do
          summary 'Excluir operação'
        end

        delete '', http_codes: [
          [204, 'No Content'],
          [401, 'Unauthorized'],
          [404, 'Not Found']
        ] do
          process_service_response(OperationService.destroy(params[:id]))
        end

        desc 'Atualizar operação' do
          summary 'Atualizar operação'
          success [code: 200, message: 'Ok', model: Api::Entities::Operation]
        end

        params do
          requires :id, type: String, desc: 'ID ou smart_id'
          optional :key, type: String, desc: 'Chave única'
          optional :title, type: String, desc: 'Título'
          optional :description, type: String, desc: 'Descrição'
          optional :keywords, type: [String, Array], desc: 'Palavras‑chave ou regex'
          optional :keywords_string, type: String, desc: 'Palavras‑chave separadas por vírgula'
          optional :active, type: Boolean, desc: 'Status ativo'
        end

        put '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(OperationService.update(params))
        end

        patch '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(OperationService.update(params))
        end
      end

      resource :stats do
        desc 'Estatísticas de operações'
        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized']
        ] do
          process_service_response(OperationService.dashboard_stats)
        end
      end

      resource :validate do
        desc 'Validar texto contra operações'
        params do
          requires :text, type: String, desc: 'Texto a validar'
        end
        post '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized']
        ] do
          process_service_response(OperationService.validate(params[:text]))
        end
      end
    end
  end
end
