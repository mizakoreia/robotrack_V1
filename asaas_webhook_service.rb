# Service genérico para processar outros webhooks do Asaas
# Processa eventos que não sejam especificamente de pagamentos de planos
class AsaasWebhookService
  class << self
    # Processa notificações genéricas do Asaas
    # @param params [Hash] Dados do webhook
    # @return [Hash] Resposta padronizada
    def process_generic_notification(params)
      Rails.logger.info "[Asaas Generic Webhook] Recebendo evento: #{params[:event]}"

      # Garantir que params é um hash com símbolos como chaves
      params = params.deep_symbolize_keys if params.respond_to?(:deep_symbolize_keys)

      # Log do evento para auditoria
      log_generic_event(params)

      # Processar eventos específicos se necessário
      case params[:event].to_s.upcase
      when 'CUSTOMER_CREATED'
        process_customer_event(params)
      when 'SUBSCRIPTION_CREATED', 'SUBSCRIPTION_UPDATED'
        process_subscription_event(params)
      when 'PAYMENT_CREATED', 'PAYMENT_RECEIVED', 'PAYMENT_CONFIRMED', 'PAYMENT_OVERDUE', 'PAYMENT_DELETED', 'PAYMENT_REFUNDED'
        # Delegar todos os eventos de pagamento para o serviço de pagamentos
        Rails.logger.info "[Asaas Generic Webhook] Delegando evento de pagamento para serviço específico: #{params[:event]}"
        AsaasPaymentWebhookService.process_payment_notification(params)
      when 'RECEIVABLE_ANTICIPATION_CREDITED'
        Rails.logger.info "[Asaas Generic Webhook] Delegando antecipação creditada para serviço específico"
        AsaasPaymentWebhookService.process_payment_notification(params)
      else
        Rails.logger.info "[Asaas Generic Webhook] Evento não processado: #{params[:event]}"
        success_response("Evento registrado")
      end

    rescue => e
      Rails.logger.error "[Asaas Generic Webhook] Erro ao processar: #{e.message}"
      Rails.logger.error "[Asaas Generic Webhook] Backtrace: #{e.backtrace.join("\n")}"
      error_response("Erro interno ao processar webhook genérico: #{e.message}")
    end

    private

    # Log de eventos genéricos para auditoria
    def log_generic_event(params)
      Rails.logger.info "[Asaas Generic Webhook] Evento: #{params[:event]}, " \
                        "Objeto: #{params[:object]}, " \
                        "Data: #{params[:dateCreated] || Time.current.iso8601}"
    end

    # Processa eventos de customer (se necessário futuramente)
    def process_customer_event(params)
      Rails.logger.info "[Asaas Generic Webhook] Processando evento de customer"
      success_response("Evento de customer processado")
    end

    # Processa eventos de subscription (para assinaturas recorrentes)
    def process_subscription_event(params)
      Rails.logger.info "[Asaas Generic Webhook] Processando evento de subscription"
      success_response("Evento de subscription processado")
    end
    
    # Processa eventos de antecipação de recebível creditada
    # @param params [Hash] Dados do webhook com informações da antecipação
    def process_anticipation_credited(params)
      Rails.logger.info "[Asaas Generic Webhook] Método legado de antecipação creditada chamado; delegando para serviço de pagamentos"
      AsaasPaymentWebhookService.process_payment_notification(params)
    end

    # Helpers de envio de PIX para antecipação
    # Método legado de envio de PIX removido deste serviço genérico.
    # O envio de PIX está centralizado no AsaasPaymentWebhookService.

    # Resposta de sucesso padronizada
    def success_response(message = "Processado com sucesso")
      {
        status: 'success',
        message: message,
        processed_at: Time.current.iso8601
      }
    end

    # Resposta de erro padronizada
    def error_response(message, status_code = 400)
      {
        status: 'error',
        message: message,
        processed_at: Time.current.iso8601,
        http_status: status_code
      }
    end

    # OBS: Métodos de pagamento foram delegados ao AsaasPaymentWebhookService.
    # Os métodos abaixo permaneceram para compatibilidade com histórico/auditoria
    # e poderão ser removidos após estabilização.
  end
end
