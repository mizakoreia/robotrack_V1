# frozen_string_literal: true

module Api
  module Whats
    module V1
      class Base < Grape::API
        format :json
        prefix :whats
        version 'v1', using: :path

        helpers do
          def process_service_response(response)
            status response[:status]

            if (200..299).include?(response[:status])
              response[:data]
            else
              error_payload = { error: response[:error] || response[:message] }
              error_payload[:details] = response[:details] if response[:details]
              error!(error_payload, response[:status])
            end
          end

          def authenticate_client_or_user!
            # Já centralizado no Root; aqui apenas garante presença
            allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user.present?)
            error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) unless allowed
          end
        end

        # Montando o namespace de mensagens
        namespace :messages do
          mount Api::Whats::V1::Messages
        end

        namespace :instances do
          mount Api::Whats::V1::Instances
        end

        namespace :webhooks do
          mount Api::Whats::V1::Webhooks
        end

        namespace :chats do
          mount Api::Whats::V1::Chats
        end

        namespace :groups do
          mount Api::Whats::V1::Groups
        end

        # Endpoint para webhook de mensagens recebidas
        resource :webhooks do
          mount Api::Whats::V1::Webhooks
        end

        # Tratamento de erros específico, se necessário
        rescue_from :all do |e|
          unless (e.is_a? Grape::Exceptions::ValidationErrors) ||
                 (e.is_a? Grape::Exceptions::MethodNotAllowed) ||
                 e.message.include?('Mysql2::Error') ||
                 (e.is_a? PG::Error)

            env = {}
            env['exception_notifier.exception_data'] = {
              api: 'API ERROR - POLEMK WHATS',
              message: e.message,
              user: 'No User.',
              environment: Rails.env
            }
          end

          # Log de erro
          error_backtrace = "ERROR - API POLEMK WHATS: #{e.message} <br/> \n BACKTRACE: #{e.backtrace.join "\n"}"
          Rails.logger.warn error_backtrace
          error!(error_backtrace)
        end

        rescue_from EvolutionConnection::InvalidResponseError do |e|
          error!(
            {
              error: e.error,
              status: e.status,
              details: e.details
            },
            422
          )
        end

        rescue_from EvolutionConnection::TimeoutError do |e|
          error!(
            {
              error: 'Timeout ao se comunicar com Evolution API',
              message: e.message
            },
            504
          )
        end

        rescue_from EvolutionConnection::ConnectionError do |e|
          error!(
            {
              error: 'Erro de conexão com Evolution API',
              message: e.message
            },
            502
          )
        end
      end
    end
  end
end
