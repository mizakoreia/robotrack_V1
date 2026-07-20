# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class Checkout < Grape::API
        format :json
        prefix :auth
        version 'v1', using: :path

        helpers do
          # Helper para processar respostas padronizadas de Services, evitando
          # repetição de lógica de status e envelopes de erro nos controllers Grape.
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
        end

        namespace :checkout do
          resource :session do
            desc 'Cria/retoma sessão após checkout concluído' do
              summary 'Sessão pós‑checkout'
              detail 'Gera sessão JWT se a conta foi criada no checkout; caso já exista, retorna requires_login: true.'
              success [code: 200, message: 'Sessão criada ou requires_login']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 404, message: 'Compra não encontrada' },
                { code: 422, message: 'Compra não confirmada' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            params do
              # Compra única
              optional :payment_id, type: String, desc: 'ID interno da compra (PAY_...)'
              optional :asaas_id, type: String, desc: 'ID do pagamento/cobrança no Asaas'
              optional :purchase_identifier, type: String, desc: 'Identificador curto da compra'
              # Assinatura
              optional :subscription_id, type: String, desc: 'ID da assinatura no Asaas'
              optional :subscription_identifier, type: String, desc: 'Identificador da assinatura'
              # Evita erro de validação rígida; trataremos na lógica abaixo
            end

            post do
              # Coleta parâmetros também via query string e aceita sinônimos em camelCase
              reqp = (request.params rescue {}) || {}
              def pick_param(h, *keys)
                keys.map { |k| h[k] }.compact.first
              end
              payment_id = pick_param(params, :payment_id) || pick_param(reqp, 'payment_id', 'paymentId')
              asaas_id = pick_param(params, :asaas_id) || pick_param(reqp, 'asaas_id', 'asaasId', 'paymentAsaasId')
              purchase_identifier = pick_param(params, :purchase_identifier) || pick_param(reqp, 'purchase_identifier', 'identifier', 'id', 'purchaseId')
              subscription_id = pick_param(params, :subscription_id) || pick_param(reqp, 'subscription_id', 'subscriptionId')
              subscription_identifier = pick_param(params, :subscription_identifier) || pick_param(reqp, 'subscription_identifier', 'subscriptionIdentifier')

              if [payment_id, asaas_id, purchase_identifier, subscription_id, subscription_identifier].all? { |v| v.nil? || v == '' }
                error!(
                  {
                    error: 'validation_error',
                    message: 'Dados inválidos',
                    details: {
                      required: ['payment_id', 'asaas_id', 'purchase_identifier', 'subscription_id', 'subscription_identifier'],
                      hint: 'Forneça pelo menos um identificador de compra ou assinatura'
                    }
                  }, 400
                )
              end

              result = ::Auth::CheckoutSessionService.new.execute!(
                payment_id: payment_id,
                asaas_id: asaas_id,
                purchase_identifier: purchase_identifier,
                subscription_id: subscription_id,
                subscription_identifier: subscription_identifier
              )
              process_service_response(result)
            end
          end
        end
      end
    end
  end
end
