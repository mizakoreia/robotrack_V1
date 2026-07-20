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

          def rate_limit_key(identifier, method)
            "magic_login:#{method}:#{identifier}"
          end

          def check_rate_limit!(identifier, method)
            rate_limit_key(identifier, method)

            # Verifica tentativas recentes
            attempts = LoginAttempt.where(
              identifier: identifier,
              method: method,
              created_at: 15.minutes.ago..Time.current,
              success: false
            ).count

            if attempts >= 5
              error!({
                       error: 'rate_limit_exceeded',
                       message: 'Muitas tentativas. Tente novamente em 15 minutos.'
                     }, 429)
            end

            # Verifica se pode solicitar novo código
            return unless method.in?(%w[email whatsapp])

            last_code = LoginCode.where(
              destination: identifier,
              method: method,
              created_at: 1.minute.ago..Time.current
            ).last

            return unless last_code && !last_code.can_resend?

            error!({
                     error: 'rate_limit_exceeded',
                     message: "Aguarde #{last_code.time_until_resend} segundos antes de solicitar um novo código"
                   }, 429)
          end

          def check_brute_force!(identifier, ip_address)
            # Verifica tentativas de força bruta por IP
            ip_attempts = LoginAttempt.where(
              ip_address: ip_address,
              created_at: 1.hour.ago..Time.current,
              success: false
            ).count

            if ip_attempts >= 20
              error!({
                       error: 'ip_blocked',
                       message: 'IP bloqueado por muitas tentativas. Contate o suporte.'
                     }, 403)
            end

            # Verifica tentativas por identificador
            id_attempts = LoginAttempt.where(
              identifier: identifier,
              created_at: 1.hour.ago..Time.current,
              success: false
            ).count

            return unless id_attempts >= 10

            error!({
                     error: 'account_blocked',
                     message: 'Conta temporariamente bloqueada por muitas tentativas'
                   }, 403)
          end
        end

        # Monta os endpoints de autenticação
        mount Api::Auth::V1::MagicLogin
        mount Api::Auth::V1::CodeValidation
        mount Api::Auth::V1::Oauth
        mount Api::Auth::V1::Sessions
        mount Api::Auth::V1::Me
        mount Api::Auth::V1::Registration
        mount Api::Auth::V1::Checkout

        # Tratamento de erro é único e vive em Api::Root.
      end
    end
  end
end
