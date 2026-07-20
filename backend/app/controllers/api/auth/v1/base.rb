# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class Base < Grape::API
        format :json
        prefix :auth
        version 'v1', using: :path

        helpers do
          def authenticate_user!
            user = env['api.current_user']
            error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) unless user
            @current_user = user
          end

          attr_reader :current_user

          def process_service_response(response)
            status response[:status]

            if (200..299).include?(response[:status])
              response[:data]
            else
              error_payload = { error: response[:error] }
              error_payload[:details] = response[:details] if response[:details]
              error!(error_payload, response[:status])
            end
          end

          def current_ip
            env['HTTP_X_FORWARDED_FOR']&.split(',')&.first || env['REMOTE_ADDR'] || '0.0.0.0'
          end

          def current_user_agent
            env['HTTP_USER_AGENT'] || 'Unknown'
          end
        end

        # Monta os endpoints de autenticação
        mount Api::Auth::V1::Oauth
        mount Api::Auth::V1::Sessions
        mount Api::Auth::V1::Me

        # Tratamento de erro é único e vive em Api::Root.
      end
    end
  end
end
