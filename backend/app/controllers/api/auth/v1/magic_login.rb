# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class MagicLogin < Grape::API
        namespace :magic_login do
          # POST /auth/v1/magic_login/request_code
          resource :request_code do
            desc 'Solicita código de acesso via email ou WhatsApp' do
              summary 'Solicitar código de login'
              detail 'Envia um código de acesso para o email ou WhatsApp informado após verificações de segurança.'
              success [code: 200, message: 'Código enviado']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 429, message: 'Muitas tentativas' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            params do
              requires :identifier, type: String, desc: 'Email ou telefone'
              requires :method, type: String, values: %w[email whatsapp], desc: 'Método de envio'
            end

            post do
              identifier = params[:identifier].strip
              delivery_method = params[:method].downcase

              stage = 'brute'
              check_brute_force!(identifier, current_ip)
              stage = 'rate'
              check_rate_limit!(identifier, delivery_method)
              stage = 'service_new'
              service = ::Auth::MagicLoginService.new(
                identifier: identifier,
                method: delivery_method,
                ip_address: current_ip,
                user_agent: current_user_agent
              )
              stage = 'execute'
              result = service.execute!
              process_service_response(result)
            rescue StandardError => e
              Rails.logger.error "🔴 ERRO: #{e.class} - #{e.message}"
              Rails.logger.error e.backtrace.first(5)
              error!({ error: e.message, stage: stage }, 500)
            end
          end

          # POST /auth/v1/magic_login/validate_code
          resource :validate_code do
            desc 'Valida código de acesso e realiza login' do
              summary 'Validar código e logar'
              detail 'Valida o código enviado ao usuário e realiza o login, retornando tokens e dados do usuário.'
              success [code: 200, message: 'Login realizado']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 401, message: 'Código inválido' },
                { code: 429, message: 'Muitas tentativas' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            params do
              requires :identifier, type: String, desc: 'Email ou telefone'
              requires :code, type: String, desc: 'Código de 6 dígitos'
              requires :method, type: String, values: %w[email whatsapp], desc: 'Método de envio'
            end

            post do
              identifier = params[:identifier].strip
              code = params[:code].strip
              method = params[:method].downcase

              # Verificações de segurança
              check_brute_force!(identifier, current_ip)

              result = ::Auth::CodeValidationService.new(
                identifier: identifier,
                code: code,
                method: method,
                ip_address: current_ip,
                user_agent: current_user_agent
              ).execute!

              process_service_response(result)
            end
          end

          # POST /auth/v1/magic_login/can_resend
          resource :can_resend do
            desc 'Verifica se pode solicitar novo código' do
              summary 'Checar status de reenvio'
              detail 'Verifica se o usuário pode solicitar um novo código e o tempo restante para reenvio.'
              success [code: 200, message: 'Status verificado']
              failure [
                { code: 400, message: 'Dados inválidos' }
              ]
            end

            params do
              requires :identifier, type: String, desc: 'Email ou telefone'
              requires :method, type: String, values: %w[email whatsapp], desc: 'Método de envio'
            end

            post do
              identifier = params[:identifier].strip
              method = params[:method].downcase

              normalized_identifier = LoginCode.normalize_destination_value(identifier)
              last_code = LoginCode.where(
                destination: normalized_identifier,
                method: method,
                created_at: 1.minute.ago..Time.current
              ).last

              can_resend = last_code.nil? || last_code.can_resend?
              time_until_resend = last_code&.time_until_resend || 0

              process_service_response({
                                         status: 200,
                                         data: {
                                           can_resend: can_resend,
                                           time_until_resend: time_until_resend
                                         }
                                       })
            end
          end
        end

        # Normalização feita via LoginCode.normalize_destination_value
      end
    end
  end
end
