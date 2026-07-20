# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class Registration < Grape::API
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

          def normalize_identifier(identifier, _method)
            LoginCode.normalize_destination_value(identifier.to_s)
          end

          def valid_email?(email)
            email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
          end

          def valid_phone?(phone)
            digits = phone.to_s.gsub(/[^0-9]/, '')
            digits.length.between?(10, 15)
          end

          def validate_identifier!(identifier, method)
            if method == 'email'
              error!({ error: 'validation_error', message: 'Email inválido' }, 400) unless valid_email?(identifier)
            else
              unless valid_phone?(identifier)
                error!({ error: 'validation_error', message: 'WhatsApp inválido (formato internacional)' },
                       400)
              end
            end
          end
        end

        resource :pre_register do
          desc 'Pré-registro: envia código para email/WhatsApp mesmo sem conta' do
            summary 'Enviar código de verificação'
            success [code: 200, message: 'Código enviado']
            failure [
              { code: 400, message: 'Dados inválidos' },
              { code: 429, message: 'Muitas tentativas' },
              { code: 500, message: 'Erro interno' }
            ]
          end

          params do
            requires :identifier, type: String, desc: 'Email ou WhatsApp'
            requires :method, type: String, values: %w[email whatsapp], desc: 'Método'
          end

          post do
            identifier = params[:identifier].to_s.strip
            method = params[:method].downcase

            result = ::Auth::PreRegisterService.new(
              identifier: identifier,
              method: method,
              ip_address: env['REMOTE_ADDR'],
              user_agent: env['HTTP_USER_AGENT']
            ).execute!
            process_service_response(result)
          end
        end

        resource :verify_code do
          desc 'Valida o código do pré-registro' do
            summary 'Verificar código'
            success [code: 200, message: 'Código válido']
            failure [
              { code: 400, message: 'Dados inválidos' },
              { code: 401, message: 'Código inválido ou expirado' },
              { code: 429, message: 'Muitas tentativas' }
            ]
          end

          params do
            requires :identifier, type: String
            requires :code, type: String
            requires :method, type: String, values: %w[email whatsapp]
          end

          post do
            identifier = params[:identifier].to_s.strip
            method = params[:method].downcase
            code = params[:code].to_s.strip

            result = ::Auth::VerifyCodeService.new(
              identifier: identifier,
              method: method,
              code: code
            ).execute!
            process_service_response(result)
          end
        end

        resource :complete_registration do
          desc 'Completa cadastro após verificação do código' do
            summary 'Completar cadastro'
            success [code: 200, message: 'Cadastro concluído']
            failure [
              { code: 400, message: 'Dados inválidos' },
              { code: 401, message: 'Código inválido ou expirado' }
            ]
          end

          params do
            requires :identifier, type: String
            requires :method, type: String, values: %w[email whatsapp]
            requires :code, type: String
            requires :name, type: String
            optional :email, type: String
            optional :whatsapp, type: String
          end

          post do
            identifier = params[:identifier].to_s.strip
            method = params[:method].downcase
            code = params[:code].to_s.strip
            name = params[:name].to_s.strip
            email = params[:email]
            whatsapp = params[:whatsapp]

            result = ::Auth::CompleteRegistrationService.new(
              identifier: identifier,
              method: method,
              code: code,
              name: name,
              email: email,
              whatsapp: whatsapp
            ).execute!
            process_service_response(result)
          end
        end
      end
    end
  end
end
