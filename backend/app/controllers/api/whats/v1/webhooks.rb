# frozen_string_literal: true

module Api
  module Whats
    module V1
      # Controller para processar webhooks de mensagens do WhatsApp
      # Processa confirmações e cancelamentos de agendamentos via códigos
      class Webhooks < Grape::API
        resource 'messages-upsert' do
          desc 'Webhook para processar mensagens recebidas do WhatsApp' do
            detail 'Recebe eventos de mensagens do Evolution API e processa confirmações/cancelamentos de agendamentos'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            #sera implementado quando tiver função que precisa processar mensagens
            #ScheduleWebhookService.process_message(params)
          end
        end

        resource 'connection-update' do
          desc 'Webhook para processar atualizações de conexão do WhatsApp' do
            detail 'Recebe eventos de mudança de status de conexão do Evolution API'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            WhatsAppWebhookService.process_connection_update(params)
          end
        end

        resource 'logout-instance' do
          desc 'Webhook para processar eventos de logout do WhatsApp' do
            detail 'Recebe eventos de logout de instância do Evolution API'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            WhatsAppWebhookService.process_logout_instance(params)
          end
        end

        resource 'qrcode-updated' do
          desc 'Webhook para processar atualizações de QR Code do WhatsApp' do
            detail 'Recebe eventos de novo QR Code do Evolution API'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            WhatsAppWebhookService.process_qrcode_updated(params)
          end
        end

        resource 'config' do
          desc 'Configurar webhook para Evolution API' do
            detail 'Cria/atualiza configuração de webhook incluindo URL, eventos e flags'
          end

          params do
            requires :url, type: String, desc: 'URL do webhook'
            optional :events, type: Array[String], desc: 'Lista de eventos'
            optional :webhookByEvents, type: Boolean, desc: 'Enviar por eventos separados'
            optional :webhookBase64, type: Boolean, desc: 'Arquivos em base64'
          end

          post '', http_codes: [
            [201, 'Configurado'],
            [401, 'Unauthorized'],
            [422, 'Unprocessable Entity'],
            [500, 'Erro interno']
          ] do
            allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed

            begin
              uri = URI.parse(params[:url])
              unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
                error!({ error: 'invalid_url', message: 'URL inválida' }, 422)
              end
            rescue URI::InvalidURIError
              error!({ error: 'invalid_url', message: 'URL inválida' }, 422)
            end

            PolemkWebhookService.create_webhook(params)
          end

          get '', http_codes: [
            [200, 'Listagem'],
            [401, 'Unauthorized']
          ] do
            allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed
            PolemkWebhookService.list(params)
          end

          post 'test', http_codes: [
            [200, 'OK'],
            [422, 'URL inválida'],
            [502, 'Erro de conexão'],
            [401, 'Unauthorized']
          ] do
            allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed

            error!({ error: 'invalid_url', message: 'URL é obrigatória' }, 422) unless params[:url].present?
            PolemkWebhookService.test_connection(params[:url])
          end
        end
      end
    end
  end
end
