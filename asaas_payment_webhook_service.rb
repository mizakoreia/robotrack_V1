# Service responsável por processar webhooks de pagamentos do Asaas
# Processa confirmações de PIX e Cartão de Crédito para compras de planos
class AsaasPaymentWebhookService
  class << self
    # Processa notificação de pagamento recebida do Asaas
    # @param params [Hash] Dados do webhook do Asaas
    # @return [Hash] Resposta padronizada da API
    def process_payment_notification(params)
      Rails.logger.info "[Asaas Webhook] Notificação recebida do Asaas"

      # Validar estrutura básica do webhook
      unless valid_webhook_structure?(params)
        return error_response("Estrutura de webhook inválida", 400)
      end

      # Extrair dados do pagamento de forma resiliente
      payment_data = extract_payment_data(params)

      # O evento pode ser PAYMENT_RECEIVED ou PAYMENT_CONFIRMED
      event = params[:event] || params['event']

      # Encontrar Purchase pela referência externa
      purchase = find_purchase_by_asaas_id(payment_data[:external_reference] || payment_data[:payment_id])

      unless purchase.present?
        return error_response("Compra não encontrada", 404)
      end

      # Processar de acordo com o status
      case event
      when 'PAYMENT_RECEIVED', 'PAYMENT_CONFIRMED'
        process_payment_confirmation(purchase, payment_data, params)
      else
        Rails.logger.info "[Asaas Webhook] Evento não relevante: #{event}"
        update_purchase_webhook_data(purchase, params)
        success_response("Evento ignorado")
      end
    rescue InvalidWebhookError => e
      error_response(e.message, 400)
    rescue => e
      Rails.logger.error "[Asaas Webhook] Erro ao processar webhook: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      error_response("Erro interno ao processar webhook", 500)
    end

    private

    # Valida estrutura básica do webhook do Asaas
    def valid_webhook_structure?(params)
      params[:event].present? &&
      (
        params[:payment].present? || params['payment'].present? ||
        params[:data].present? || params['data'].present? ||
        params[:anticipation].present? || params['anticipation'].present?
      )
    end

    # Atualiza dados de webhook para auditoria
    def update_purchase_webhook_data(purchase, webhook_params)
      purchase.update(webhook_data: webhook_params.to_h)
    end

    # Extrai dados relevantes do webhook para processamento de pagamento
    def extract_payment_data(params)
      payment = params[:payment] || params['payment'] || params[:data] || params['data'] || {}

      {
        payment_id: payment[:id] || payment['id'],
        status: payment[:status] || payment['status'],
        value: (payment[:value] || payment['value']).to_f,
        net_value: (payment[:netValue] || payment['netValue'] || payment[:value] || payment['value']).to_f,
        external_reference: payment[:externalReference] || payment['externalReference'],
        customer_id: payment[:customer] || payment['customer']
      }
    end

    # Busca Purchase pelo asaas_id (externalReference do pagamento)
    def find_purchase_by_asaas_id(asaas_id)
      return nil unless asaas_id.present?

      Purchase.find_by(identifier: asaas_id.to_s)
    end

    # Processa confirmação de pagamento (PIX ou Cartão confirmado)
    # Implementa proteção contra webhooks duplicados
    def process_payment_confirmation(purchase, payment_data, webhook_params)
      Rails.logger.info "[Asaas Webhook] Processando confirmação para Purchase #{purchase.id}"

      net_value = payment_data[:net_value].to_f.nonzero? || payment_data[:value].to_f

      # PROTEÇÃO CONTRA WEBHOOKS DUPLICADOS
      # Se Purchase já está DONE, apenas atualiza webhook_data mas não reprocessa
      if purchase.done?
        Rails.logger.info "[Asaas Webhook] Purchase #{purchase.id} já confirmada (DONE), ignorando reprocessamento"
        Rails.logger.info "[Asaas Webhook] Atualizando apenas webhook_data para registro de auditoria"

        # Atualizar apenas os dados do webhook para auditoria, sem alterar status
        update_purchase_webhook_data(purchase, webhook_params)

        # Ainda assim, garantir pagamento de comissão/PIX se necessário
        if purchase.referral_code_id.present?
          commission = Commission.find_by(
            purchase_id: purchase.id,
            referral_code_id: purchase.referral_code_id
          )

          if commission.present?
            unless commission.status == 'PAID'
              process_commission_and_pix(purchase, payment_data, net_value, commission)
            end
          else
            process_commission_and_pix(purchase, payment_data, net_value)
          end
        end

        return success_response("Pagamento já processado anteriormente - webhook registrado para auditoria")
      end

      # Atualizar Purchase para DONE apenas se ainda não estava DONE
      purchase.update!(
        status: 'DONE',
        webhook_data: webhook_params.to_h,
        payment_data: payment_data
      )

      Rails.logger.info "[Asaas Webhook] Purchase #{purchase.id} atualizada para DONE"

      # Criar/associar usuário ao confirmar pagamento, quando aplicável
      begin
        purchase.ensure_user_account!
      rescue => e
        Rails.logger.error "[Asaas Webhook] Falha ao garantir conta do usuário: #{e.message}"
      end

      # Registrar comissão e enviar PIX
      if purchase.referral_code_id.present?
        commission = Commission.find_by(
          purchase_id: purchase.id,
          referral_code_id: purchase.referral_code_id
        )

        if commission.present?
          commission.update(
            status: 'CONFIRMED',
            payment_data: payment_data.to_h
          )

          process_commission_and_pix(purchase, payment_data, net_value, commission)
        else
          process_commission_and_pix(purchase, payment_data, net_value)
        end
      end

      # Enviar notificações WhatsApp apenas na primeira confirmação
      send_payment_notifications(purchase)

      # Enviar notificação via WebSocket em tempo real para o frontend
      send_websocket_notification(purchase)

      # Log de telemetria
      log_payment_confirmation(purchase, payment_data)

      success_response("Pagamento confirmado com sucesso")
    end

    # Envia notificações em canais
    def send_payment_notifications(purchase)
      # Implementação real omitida
    end

    # Envia notificação via WebSocket
    def send_websocket_notification(purchase)
      # Implementação real omitida
    end

    # Log de telemetria para confirmação
    def log_payment_confirmation(purchase, payment_data)
      Rails.logger.info "[Asaas Webhook Telemetria] Purchase confirmada: #{purchase.id}, " \
                        "Método: #{purchase.billing_type}, " \
                        "Valor: #{purchase.value}, " \
                        "Status Asaas: #{payment_data[:status]}"
    end

    # Helpers de comissão e PIX
    # Processa comissão e prepara PIX para o parceiro
    # @param purchase [Purchase] Objeto da compra
    # @param payment_data [Hash] Dados do pagamento
    # @param net_value [Float] Valor líquido do pagamento
    # @param commission [Commission] Comissão existente (opcional)
    def process_commission_and_pix(purchase, payment_data, net_value, commission = nil)
      # Buscar o código de afiliado
      referral_code = ReferralCode.find_by(id: purchase.referral_code_id)
      return unless referral_code.present?

      # Calcular valor da comissão baseado no net_value e na porcentagem do cupom
      commission_percentage = referral_code.percentage.to_f
      commission_value = (net_value * commission_percentage / 100.0).round(2)

      # Verificar se já existe um CommissionPayment para esta compra/código
      existing_payment = CommissionPayment.where(
        purchase_id: purchase.id,
        referral_code_id: referral_code.id
      ).where(status: ['PIX_SENT', 'PENDING_PIX', 'PAID']).order(payment_date: :desc).first

      if existing_payment.present?
        Rails.logger.info "[Asaas Webhook] Pagamento de comissão já existe: #{existing_payment.id} com status #{existing_payment.status}"
        return existing_payment
      end

      # Usar comissão existente ou criar uma nova
      unless commission.present?
        commission = Commission.find_or_initialize_by(
          purchase_id: purchase.id,
          referral_code_id: referral_code.id
        )

        if commission.new_record?
          commission.assign_attributes(
            expected_value: commission_value,
            status: 'CONFIRMED'
          )
          commission.save!
        else
          commission.update!(
            expected_value: commission_value,
            status: 'CONFIRMED'
          )
        end
      else
        commission.update!(
          expected_value: commission_value,
          status: 'CONFIRMED'
        )
      end

      # Enviar PIX para o parceiro - CommissionPayment será registrado via Commission#register_payment após envio PIX
      send_pix_to_partner(commission, referral_code, payment_data, net_value)

      commission
    end

    # Envia PIX para o parceiro
    # @param commission [Commission] Objeto da comissão
    # @param referral_code [ReferralCode] Código de afiliado
    # @param payment_data [Hash] Dados do pagamento
    # @param net_value [Float] Valor líquido do pagamento
    def send_pix_to_partner(commission, referral_code, payment_data, net_value)
      user = Livetat::Auth::User.find_by(id: referral_code.user_id)
      return unless user.present?

      # Verificar se o usuário tem chave PIX cadastrada
      unless user.pix_key.present? && user.pix_key_type.present?
        Rails.logger.error "[Asaas Webhook] Usuário #{user.id} não possui chave PIX cadastrada"
        return
      end

      # Normalizar e validar chave PIX
      pix_type = normalize_pix_key_type(user.pix_key_type)
      pix_key  = normalize_pix_key(user.pix_key, pix_type)
      unless valid_pix_key?(pix_key, pix_type)
        Rails.logger.error "[Asaas Webhook] Chave PIX inválida para usuário #{user.id}: tipo=#{pix_type}, chave=#{pix_key}"
        return
      end

      # Preparar dados para envio do PIX
      pix_data = {
        value: commission.expected_value,
        pixAddressKey: pix_key,
        pixAddressKeyType: pix_type,
        operationType: 'PIX',
        description: "Pagamento de comissão referente à compra #{commission.purchase_id}",
        externalReference: "commission_#{commission.id}"
      }

      # Enviar PIX
      begin
        response = AsaasConnection.send_pix(pix_data)
        success = response[:status] == 'success'
        payload = response[:response]

        # Registrar pagamento na comissão com método PIX
        payment = commission.register_payment(
          commission.expected_value,
          'PIX',
          nil,
          payload
        )

        # Mapear status da transferência e atualizar CommissionPayment
        mapped_status = map_asaas_transfer_status(payload)
        begin
          payment.update(status: mapped_status) if payment && mapped_status
        rescue => e
          Rails.logger.warn "[Asaas Webhook] Falha ao atualizar status do CommissionPayment: #{e.message}"
        end

        transfer_id = (payload['id'] || payload.dig('transfer', 'id') || payload.dig('data', 'id'))
        if success
          Rails.logger.info "[Asaas Webhook] PIX enviado com sucesso para parceiro #{user.id}, valor: #{commission.expected_value}, id: #{transfer_id}, externalReference: #{pix_data[:externalReference]}"
        else
          Rails.logger.error "[Asaas Webhook] Erro ao enviar PIX para parceiro #{user.id}: #{payload.inspect}"
        end

        return payment
      rescue AsaasConnection::InvalidResponseError => e
        Rails.logger.error "[Asaas Webhook] Erro de resposta Asaas: #{e.error} - #{e.details}"
        # Registrar pagamento parcial/erro se necessário (não registra quando falha total)
        return false
      rescue => e
        Rails.logger.error "[Asaas Webhook] Exceção ao enviar PIX para parceiro #{user.id}: #{e.message}"
        Rails.logger.error "[Asaas Webhook] Backtrace: #{e.backtrace.join("\n")}"
        return false
      end
    end

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

    # =========================
    # Validação de chaves PIX
    # =========================
    def normalize_pix_key_type(type)
      type.to_s.strip.upcase
    end

    def normalize_pix_key(key, type)
      k = key.to_s.strip
      case type
      when 'CPF', 'CNPJ'
        k.gsub(/\D/, '')
      when 'PHONE'
        digits = k.gsub(/\D/, '')
        digits = "55#{digits}" unless digits.start_with?('55')
        "+#{digits}"
      when 'EMAIL'
        k.downcase
      when 'EVP'
        k
      else
        k
      end
    end

    def valid_pix_key?(key, type)
      case type
      when 'CPF'  then valid_cpf?(key)
      when 'CNPJ' then valid_cnpj?(key)
      when 'EMAIL' then valid_email?(key)
      when 'PHONE' then valid_phone?(key)
      when 'EVP' then valid_evp?(key)
      else
        false
      end
    end

    def valid_cpf?(cpf)
      digits = cpf.to_s.gsub(/\D/, '')
      return false unless digits.length == 11
      return false if %w[00000000000 11111111111 22222222222 33333333333 44444444444 55555555555 66666666666 77777777777 88888888888 99999999999].include?(digits)
      sum1 = (0..8).sum { |i| digits[i].to_i * (10 - i) }
      d1 = sum1 % 11
      d1 = (d1 < 2) ? 0 : 11 - d1
      sum2 = (0..9).sum { |i| digits[i].to_i * (11 - i) }
      d2 = sum2 % 11
      d2 = (d2 < 2) ? 0 : 11 - d2
      digits[9].to_i == d1 && digits[10].to_i == d2
    end

    def valid_cnpj?(cnpj)
      digits = cnpj.to_s.gsub(/\D/, '')
      return false unless digits.length == 14
      return false if %w[00000000000000 11111111111111 22222222222222 33333333333333 44444444444444 55555555555555 66666666666666 77777777777777 88888888888888 99999999999999].include?(digits)
      weights1 = [5,4,3,2,9,8,7,6,5,4,3,2]
      sum1 = (0..11).sum { |i| digits[i].to_i * weights1[i] }
      d1 = sum1 % 11
      d1 = (d1 < 2) ? 0 : 11 - d1
      weights2 = [6,5,4,3,2,9,8,7,6,5,4,3,2]
      sum2 = (0..12).sum { |i| digits[i].to_i * weights2[i] }
      d2 = sum2 % 11
      d2 = (d2 < 2) ? 0 : 11 - d2
      digits[12].to_i == d1 && digits[13].to_i == d2
    end

    def valid_email?(email)
      !!(email =~ /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
    end

    def valid_phone?(phone)
      # E.164: +[country][number], Brazil prefix 55 required
      !!(phone =~ /\A\+[1-9]\d{7,14}\z/)
    end

    def valid_evp?(evp)
      # UUID-like or long random string
      uuid_regex = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z/
      evp.to_s.match?(uuid_regex) || evp.to_s.length >= 16
    end
  end
end

def map_asaas_transfer_status(payload)
  status = payload['status'] || payload.dig('transfer', 'status') || payload.dig('data', 'status')
  case status.to_s.upcase
  when 'DONE', 'PROCESSED', 'COMPLETED'
    'PAID'
  when 'PENDING', 'AWAITING_APPROVAL'
    'PENDING_PIX'
  when 'CANCELED', 'CANCELLED', 'FAILED', 'ERROR'
    'PIX_FAILED'
  else
    'PIX_SENT'
  end
end
