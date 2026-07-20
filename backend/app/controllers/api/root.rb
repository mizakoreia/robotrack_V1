# frozen_string_literal: true

require 'grape'
require_relative './v1/controller_helpers'
require 'grape-swagger'
require 'grape-swagger-entity'

module Api
  class Root < Grape::API
    format :json
    # Sem prefixo/version global; cada módulo define seu próprio prefixo e versão

    # Única lista de rotas servidas sem autenticação. Qualquer caminho fora
    # daqui exige `Authorization: Bearer` válido — não há header, env var ou
    # token de aplicação que desligue essa verificação.
    PUBLIC_ROUTES = [
      %r{^/swagger_doc},
      %r{^/api/v1/countries/?$},
      %r{^/auth/v1/oauth/google_url/?$},
      %r{^/auth/v1/oauth/callback/?$}
    ].freeze

    before do
      next if PUBLIC_ROUTES.any? { |regex| request.path =~ regex }

      # Centraliza autenticação: Warden/Devise JWT ou decoder próprio.
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

        error!({ error: 'unauthorized', message: 'Token inválido' }, 401) unless user
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
    end

    # Montando os módulos da API (cada um com seu prefixo e versão)
    mount Api::Auth::V1::Base     # /auth/v1/*
    mount Api::Whats::V1::Base    # /whats/v1/*
    mount Api::V1::Base

    # Único tratamento de erro da API — as cópias em Api::V1::Base e
    # Api::Auth::V1::Base foram removidas. O backtrace vai para o log, nunca
    # para o corpo da resposta.
    rescue_from :all do |e|
      request_id = env['action_dispatch.request_id'] || SecureRandom.uuid

      if e.is_a?(Grape::Exceptions::ValidationErrors)
        error!({ error: 'validation_error', message: 'Dados inválidos', details: e.errors, request_id: }, 400)
      end

      Rails.logger.error(
        {
          event: 'api_error',
          request_id:,
          exception: e.class.name,
          message: e.message,
          backtrace: Array(e.backtrace).first(30)
        }.to_json
      )

      ErrorReporter.report(e, context: { request_id:, path: request.path, method: request.request_method })

      error!({ error: 'internal_error', message: 'Erro interno no servidor', request_id: }, 500)
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
