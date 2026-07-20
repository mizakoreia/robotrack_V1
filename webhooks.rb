module Api
  module Asaas
    module V1
      # Controller para processar webhooks de pagamentos do Asaas
      # Recebe notificações de confirmação de pagamentos PIX e Cartão
      class Webhooks < Grape::API

        # Webhook principal para notificações de pagamentos
        resource :payment_notification do
          desc "Webhook para processar notificações de pagamento do Asaas" do
            detail "Recebe eventos de pagamentos do Asaas e processa confirmações/alterações de status"
          end

          params do
          end

          post "", http_codes: [
            [200, "Processado com sucesso"],
            [400, "Dados inválidos"],
            [404, "Pagamento não encontrado"],
            [500, "Erro interno"]
          ] do
            AsaasPaymentWebhookService.process_payment_notification(params)
          end
        end

        # Webhook genérico para outros tipos de eventos do Asaas
        resource :generic_notification do
          desc "Webhook genérico para eventos do Asaas" do
            detail "Processa outros tipos de eventos que possam ser enviados pelo Asaas"
          end

          params do
            requires :event, type: String, desc: "Tipo do evento"
            optional :object, type: String, desc: "Tipo do objeto"
            optional :data, type: Hash, desc: "Dados do evento"
          end

          post "", http_codes: [
            [200, "Processado com sucesso"],
            [400, "Dados inválidos"],
            [500, "Erro interno"]
          ] do
            AsaasWebhookService.process_generic_notification(params)
          end
        end
      end
    end
  end
end
