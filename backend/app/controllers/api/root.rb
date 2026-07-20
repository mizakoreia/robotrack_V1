# frozen_string_literal: true

require 'grape'
require_relative './v1/controller_helpers'
require 'grape-swagger'
require 'grape-swagger-entity'

module Api
  class Root < Grape::API
    format :json
    # Sem prefixo/version global; cada módulo define seu próprio prefixo e versão

    before do
      skip_header = (headers['X-Skip-Auth'] == '1') || (headers['HTTP_X_SKIP_AUTH'] == '1')
      next if skip_header

      # Ignora autenticação para webhooks, swagger e endpoints públicos de auth
      public_paths = [
        %r{^/swagger_doc},
        %r{^/api/v1/countries/?$},

        %r{^/whats/v1/webhooks/messages-upsert/?$},
        %r{^/whats/v1/webhooks/qrcode-updated/?$},
        %r{^/whats/v1/webhooks/send-message/?$},
        %r{^/whats/v1/webhooks/messages-update/?$},
        %r{^/whats/v1/webhooks/connection-update/?$},
        %r{^/whats/v1/webhooks/logout-instance/?$},
        %r{^/auth/v1/magic_login/request_code/?$},
        %r{^/auth/v1/magic_login/validate_code/?$},
        %r{^/auth/v1/code_validation/?$},
        %r{^/auth/v1/magic_login/can_resend/?$},
        %r{^/auth/v1/oauth/google_url/?$},
        %r{^/auth/v1/oauth/facebook_url/?$},
        %r{^/auth/v1/oauth/callback/?$},
        %r{^/auth/v1/pre_register/?$},
        %r{^/auth/v1/verify_code/?$},
        %r{^/auth/v1/complete_registration/?$},
        %r{^/auth/v1/sessions/status/?$},
        %r{^/auth/v1/checkout/session/?$},
        
        # status exige auth para gerar CSRF corretamente
      ]

      next if public_paths.any? { |regex| request.path =~ regex }


      # Centraliza autenticação: Warden/Devise JWT ou decoder próprio; fallback para ClientApplication
      user = nil
      user = env['warden'].authenticate if defined?(Warden) && env['warden']

      unless user
        auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
        error!({ error: 'unauthorized', message: 'Authorization header ausente' }, 401) if auth_header.blank?

        scheme, token = auth_header.split(' ')
        unless scheme == 'Bearer' && token.present?
          error!({ error: 'unauthorized', message: 'Formato do Authorization inválido' },
                 401)
        end

        begin
          payload = nil
          payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
          payload ||= Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
          user = User.find_by(id: payload['sub']) if payload && payload['sub']
        rescue StandardError
          user = nil
        end

        unless user
          @current_client = ClientApplication.active.find_by(token: token)
          error!({ error: 'unauthorized', message: 'Token inválido' }, 401) unless @current_client
          env['api.current_client'] = @current_client
          next
        end
      end

      @current_user = user
      env['api.current_user'] = @current_user
    end

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

      attr_reader :current_user

      attr_reader :current_client
    end

    # Montando os módulos da API (cada um com seu prefixo e versão)
    mount Api::Auth::V1::Base     # /auth/v1/*
    mount Api::Whats::V1::Base    # /whats/v1/*
    mount Api::V1::Base

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
        ExceptionNotifier.notify_exception(e, env: env)
      end

      # Log de erro
      error_backtrace = "ERROR - API POLEMK WHATS: #{e.message} <br/> \n BACKTRACE: #{e.backtrace.join "\n"}"
      Rails.logger.warn error_backtrace
      error!(error_backtrace)
    end

    add_swagger_documentation(
      mount_path: '/swagger_doc',
      hide_documentation_path: true,
      format: :json,
      base_path: '/',
      info: {
        title: ENV.fetch('APP_NAME', 'robotrack'),
        description: "API do #{ENV.fetch('APP_NAME',
                                         'robotrack')} para integrações (WhatsApp/Evolution, Pagamentos/Asaas, Auth)."
      },
      security_definitions: {
        Bearer: {
          type: 'apiKey',
          name: 'Authorization',
          in: 'header',
          description: 'Token de autenticação no formato: Bearer {token}'
        }
      },
      security: [{ Bearer: [] }]
    )
  end
end
