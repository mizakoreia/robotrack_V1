# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class CodeValidation < Grape::API
        namespace :code_validation do
          # POST /auth/v1/code_validation
          resource '' do
            desc 'Valida código de acesso (alias para magic_login/validate_code)' do
              summary 'Validar código e logar (alias)'
              detail 'Valida o código enviado ao usuário e realiza o login. Alias de magic_login/validate_code.'
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

            post '', http_codes: [
              [200, 'Login realizado'],
              [400, 'Dados inválidos'],
              [401, 'Código inválido'],
              [429, 'Muitas tentativas'],
              [500, 'Erro interno']
            ] do
              identifier = params[:identifier].strip
              code = params[:code].strip
              method = params[:method].downcase

              # Verificações de segurança
              check_brute_force!(identifier, env['REMOTE_ADDR'])

              result = Auth::CodeValidationService.new(
                identifier: identifier,
                code: code,
                method: method,
                ip_address: env['REMOTE_ADDR'],
                user_agent: env['HTTP_USER_AGENT']
              ).execute!

              process_service_response(result)
            end
          end
        end
      end
    end
  end
end
