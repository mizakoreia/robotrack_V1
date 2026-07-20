# frozen_string_literal: true

module Api
  module V1
    class LeadMessages < Grape::API
      helpers Api::V1::ControllerHelpers
      # Lista mensagens de um lead
      resource '' do
        desc 'Listar mensagens do lead' do
          summary 'Listar mensagens do lead'
          detail 'Retorna uma lista de mensagens do lead com filtros opcionais.'
          success [code: 200, message: 'Ok', model: Api::Entities::LeadMessage]
          is_array true
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead (aceita by_any_id)'
          optional :o, type: Integer, desc: 'Offset'
          optional :l, type: Integer, desc: 'Limit'
          optional :q, type: String, desc: 'Busca por conteúdo'
        end

        get ':lead_id/messages', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [404, 'Lead not found'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(LeadMessageService.list(params))
        end
      end

      # Criar mensagem para um lead
      resource '' do
        desc 'Criar mensagem' do
          summary 'Criar mensagem'
          detail 'Cria uma mensagem para um lead.'
          success [code: 201, message: 'Created', model: Api::Entities::LeadMessage]
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead (aceita by_any_id)'
          requires :sender_role, type: String, desc: 'Papel do remetente (user|agent|admin)'
          requires :content, type: String, desc: 'Conteúdo da mensagem'
          optional :content_type, type: String, desc: 'Tipo de conteúdo (text|image|audio|video|file|document)'
          optional :agent_type, type: String, desc: 'Tipo/nome do agente'
          optional :instruction, type: String, desc: 'Instrução contextual'
          optional :group_id, type: Integer, desc: 'ID do grupo (bulk)'
          optional :user_id, type: String, desc: 'UUID do usuário (se sender_role=user/admin)'
          optional :media_url, type: String, desc: 'URL de mídia (se não text)'
          optional :media_mime, type: String, desc: 'MIME da mídia (se não text)'
          optional :source_message_id, type: String, desc: 'ID original da mensagem na fonte (wamid/mid)'
        end

        post ':lead_id/messages', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Lead not found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(LeadMessageService.create(params))
        end
      end

      # Criar mensagens em massa para um lead
      resource '' do
        desc 'Criar mensagens em massa' do
          summary 'Criar mensagens em massa'
          detail 'Cria várias mensagens para um lead.'
          success [code: 201, message: 'Created', model: Api::Entities::LeadMessage]
          is_array true
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead (aceita by_any_id)'
          optional :group_id, type: Integer, desc: 'ID do grupo (gerado automaticamente se ausente)'
          requires :messages, type: Array, desc: 'Array de mensagens' do
            requires :sender_role, type: String, desc: 'Papel do remetente (user|agent|admin)'
            requires :content, type: String, desc: 'Conteúdo da mensagem'
            optional :content_type, type: String, desc: 'Tipo de conteúdo'
            optional :agent_type, type: String, desc: 'Tipo/nome do agente'
            optional :instruction, type: String, desc: 'Instrução contextual'
            optional :user_id, type: String, desc: 'UUID do usuário (se sender_role=user/admin)'
            optional :media_url, type: String, desc: 'URL de mídia'
            optional :media_mime, type: String, desc: 'MIME da mídia'
            optional :source_message_id, type: String, desc: 'ID original da mensagem na fonte (wamid/mid)'
          end
        end

        post ':lead_id/messages/bulk', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Lead not found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(LeadMessageService.create_bulk(params))
        end
      end

      # Obter mensagem por ID
      resource :messages do
        desc 'Buscar mensagem' do
          summary 'Buscar mensagem'
          success [code: 200, message: 'Ok', model: Api::Entities::LeadMessage]
        end

        params do
          requires :id, type: String, desc: 'ID da mensagem (aceita by_any_id)'
        end

        get ':id', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(LeadMessageService.get_message(params[:id]))
        end

        desc 'Atualizar mensagem' do
          summary 'Atualizar mensagem'
          success [code: 200, message: 'Ok', model: Api::Entities::LeadMessage]
        end

        params do
          requires :id, type: String, desc: 'ID da mensagem (aceita by_any_id)'
          optional :content, type: String, desc: 'Conteúdo da mensagem'
          optional :agent_type, type: String, desc: 'Tipo/nome do agente'
          optional :instruction, type: String, desc: 'Instrução contextual'
          optional :group_id, type: Integer, desc: 'ID do grupo'
          optional :content_type, type: String, desc: 'Tipo de conteúdo'
          optional :media_url, type: String, desc: 'URL de mídia'
          optional :media_mime, type: String, desc: 'MIME da mídia'
          optional :source_message_id, type: String, desc: 'ID original da mensagem na fonte (wamid/mid)'
        end

        patch ':id', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity']
        ] do
          update_params = params.dup
          process_service_response(LeadMessageService.update(update_params))
        end

        delete ':id', http_codes: [
          [204, 'No Content'],
          [401, 'Unauthorized'],
          [404, 'Not Found']
        ] do
          process_service_response(LeadMessageService.destroy(params[:id]))
        end
      end
    end
  end
end
