# frozen_string_literal: true

# Serviço para processar webhooks do WhatsApp (Evolution API)
# Responsável por tratar eventos de conexão, logout e QR Code
class WhatsAppWebhookService
  class << self
    # Processa eventos de atualização de conexão
    # @param params [Hash] payload do webhook
    # @return [Hash] resposta de processamento
    def process_connection_update(params)
      Rails.logger.info('[WhatsAppWebhookService] Processing CONNECTION_UPDATE webhook')

      # Valida estrutura básica do payload
      validation_result = validate_connection_update_payload(params)
      return validation_result unless validation_result[:status] == 'success'

      # Extrai dados do payload
      event_data = params[:data] || {}
      instance_id = params[:instanceId] || params[:instance] || event_data[:instance]
      connection_status = event_data[:state] || event_data[:connection]
      status_reason = event_data[:statusReason]

      Rails.logger.info("[WhatsAppWebhookService] Connection update - Instance: #{instance_id}, Status: #{connection_status}, Reason: #{status_reason}")

      # Busca instância no banco de dados
      instance = find_instance_by_identifier(instance_id)
      if instance.nil?
        Rails.logger.warn("[WhatsAppWebhookService] Instance not found: #{instance_id}")
        return { status: 'error', message: 'Instância não encontrada' }
      end

      # Atualiza status da instância
      update_instance_connection_status(instance, connection_status, event_data)

      # Broadcast do evento para clientes conectados
      broadcast_connection_update(instance, connection_status, event_data)

      Rails.logger.info('[WhatsAppWebhookService] CONNECTION_UPDATE processed successfully')
      { status: 'success', message: 'Conexão atualizada com sucesso' }
    rescue StandardError => e
      Rails.logger.error("[WhatsAppWebhookService] Error processing CONNECTION_UPDATE: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      { status: 'error', message: 'Erro ao processar atualização de conexão' }
    end

    # Processa eventos de logout
    # @param params [Hash] payload do webhook
    # @return [Hash] resposta de processamento
    def process_logout_instance(params)
      Rails.logger.info('[WhatsAppWebhookService] Processing LOGOUT_INSTANCE webhook')
      # Valida estrutura básica do payload
      validation_result = validate_logout_payload(params)
      return validation_result unless validation_result[:status] == 'success'

      # Extrai dados do payload
      event_data = params[:data] || {}
      instance_id = params[:instanceId] || params[:instance] || event_data[:instance]
      logout_reason = event_data[:reason] || 'logout'
      logout_initiator = params[:sender]
      timestamp = params[:date_time]

      Rails.logger.info("[WhatsAppWebhookService] Logout instance - Instance: #{instance_id}, Reason: #{logout_reason}")

      # Busca instância no banco de dados
      instance = find_instance_by_identifier(instance_id)
      if instance.nil?
        Rails.logger.warn("[WhatsAppWebhookService] Instance not found: #{instance_id}")
        return { status: 'error', message: 'Instância não encontrada' }
      end

      # Processa logout da instância
      process_instance_logout(instance, logout_reason, timestamp, logout_initiator)

      # Broadcast do evento para clientes conectados
      broadcast_logout_event(instance, logout_reason, timestamp)

      Rails.logger.info('[WhatsAppWebhookService] LOGOUT_INSTANCE processed successfully')
      { status: 'success', message: 'Logout processado com sucesso' }
    rescue StandardError => e
      Rails.logger.error("[WhatsAppWebhookService] Error processing LOGOUT_INSTANCE: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      { status: 'error', message: 'Erro ao processar logout' }
    end

    # Processa eventos de atualização de QR Code
    # @param params [Hash] payload do webhook
    # @return [Hash] resposta de processamento
    def process_qrcode_updated(params)
      Rails.logger.info('[WhatsAppWebhookService] Processing QRCODE_UPDATED webhook')

      # Valida estrutura básica do payload
      validation_result = validate_qrcode_payload(params)
      return validation_result unless validation_result[:status] == 'success'

      # Extrai dados do payload
      event_data = params[:data] || {}
      qr_obj = event_data[:qrcode] || {}
      instance_id = params[:instanceId] || params[:instance] || qr_obj[:instance]
      qr_code = qr_obj[:base64] || event_data[:qr]
      expires_in = nil
      session = qr_obj[:pairingCode]

      Rails.logger.info("[WhatsAppWebhookService] QR Code updated - Instance: #{instance_id}, Expires in: #{expires_in}s")

      # Busca instância no banco de dados
      instance = find_instance_by_identifier(instance_id)
      if instance.nil?
        Rails.logger.warn("[WhatsAppWebhookService] Instance not found: #{instance_id}")
        return { status: 'error', message: 'Instância não encontrada' }
      end

      # Atualiza QR Code da instância
      update_instance_qr_code(instance, qr_code, expires_in, session)

      # Broadcast do evento para clientes conectados
      broadcast_qrcode_update(instance, qr_code, expires_in, session)

      Rails.logger.info('[WhatsAppWebhookService] QRCODE_UPDATED processed successfully')
      { status: 'success', message: 'QR Code atualizado com sucesso' }
    rescue StandardError => e
      Rails.logger.error("[WhatsAppWebhookService] Error processing QRCODE_UPDATED: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      { status: 'error', message: 'Erro ao processar QR Code' }
    end

    private

    def find_instance_by_identifier(identifier)
      return nil if identifier.blank?

      PolemkInstance.find_by(instance_id: identifier) || PolemkInstance.find_by(instance_name: identifier) || PolemkInstance.where(id: identifier).first
    end

    # Valida payload de CONNECTION_UPDATE
    def validate_connection_update_payload(params)
      return { status: 'error', message: 'Payload vazio' } if params.blank?
      return { status: 'error', message: 'data não fornecido' } if params[:data].blank?

      event_data = params[:data]
      if event_data[:state].blank? && event_data[:connection].blank?
        return { status: 'error',
                 message: 'connection status não fornecido' }
      end

      has_instance = params[:instanceId].present? || params[:instance].present? || event_data[:instance].present?
      return { status: 'error', message: 'Instância não fornecida' } unless has_instance

      { status: 'success' }
    end

    # Valida payload de LOGOUT_INSTANCE
    def validate_logout_payload(params)
      return { status: 'error', message: 'Payload vazio' } if params.blank?

      event_data = params[:data] || {}
      has_instance = params[:instanceId].present? || params[:instance].present? || event_data[:instance].present?
      return { status: 'error', message: 'Instância não fornecida' } unless has_instance

      { status: 'success' }
    end

    # Valida payload de QRCODE_UPDATED
    def validate_qrcode_payload(params)
      return { status: 'error', message: 'Payload vazio' } if params.blank?
      return { status: 'error', message: 'data não fornecido' } if params[:data].blank?

      event_data = params[:data]
      qr_obj = event_data[:qrcode] || {}
      has_qr = qr_obj[:base64].present? || event_data[:qr].present?
      return { status: 'error', message: 'QR Code não fornecido' } unless has_qr

      has_instance = params[:instanceId].present? || params[:instance].present? || qr_obj[:instance].present?
      return { status: 'error', message: 'Instância não fornecida' } unless has_instance

      { status: 'success' }
    end

    # Atualiza status de conexão da instância
    def update_instance_connection_status(instance, connection_status, event_data)
      # Mapeia status da Evolution para status interno
      internal_status = map_connection_status(connection_status)

      # Atualiza dados da instância
      instance.update_columns(
        connection_status: internal_status,
        last_connection_at: Time.current,
        connection_data: event_data.to_json
      )

      Rails.logger.info("[WhatsAppWebhookService] Instance #{instance.instance_id} connection status updated to #{internal_status}")

      ensure_default_group_for_instance(instance, internal_status)
    end

    # Processa logout da instância
    def process_instance_logout(instance, logout_reason, timestamp, logout_initiator = nil)
      # Converte timestamp para datetime se fornecido
      logout_time = timestamp ? Time.at(timestamp / 1000) : Time.current

      # Atualiza dados da instância
      instance.update_columns(
        connection_status: 'disconnected',
        last_logout_at: logout_time,
        logout_reason: logout_reason,
        logout_initiator: logout_initiator,
        last_connection_at: nil
      )

      # Limpa dados sensíveis
      instance.clear_connection_data

      Rails.logger.info("[WhatsAppWebhookService] Instance #{instance.instance_id} logged out - Reason: #{logout_reason} - Initiator: #{logout_initiator}")
    end

    # Atualiza QR Code da instância
    def update_instance_qr_code(instance, qr_code, expires_in, session)
      # Calcula tempo de expiração
      expires_at = expires_in&.to_i&.positive? ? Time.current + expires_in.to_i.seconds : nil

      # Atualiza dados da instância
      instance.update_columns(
        qr_code: qr_code,
        qr_expires_at: expires_at,
        qr_session: session,
        last_qr_generated_at: Time.current
      )

      Rails.logger.info("[WhatsAppWebhookService] Instance #{instance.instance_id} QR Code updated")
    end

    # Mapeia status da Evolution para status interno
    def map_connection_status(evolution_status)
      case evolution_status.downcase
      when 'connecting'
        'connecting'
      when 'open'
        'connected'
      when 'close'
        'disconnected'
      when 'qr'
        'waiting_qr'
      else
        'unknown'
      end
    end

    def ensure_default_group_for_instance(instance, internal_status)
      return unless internal_status == 'connected'
      return if PolemkInstanceGroup.exists?(polemk_instance_id: instance.id)

      begin
        default_participant = '5548984567304'
        params_group = {
          description: "Grupo padrão da instância #{instance.display_name}",
          participants: [default_participant]
        }
        response = EvolutionConnection.create_group(params_group)
        group_id = response[:response].dig('data',
                                           'id') || response[:response].dig('group', 'id') || response[:response]['id']
        group_name = response[:response].dig('data',
                                             'subject') || response[:response].dig('group',
                                                                                   'name') || "Grupo #{instance.display_name}"

        PolemkInstanceGroup.create!(
          polemk_instance_id: instance.id,
          group_id: group_id,
          group_name: group_name,
          raw_response: response[:response]
        )
        Rails.logger.info("[WhatsAppWebhookService] Grupo criado para instância #{instance.instance_id}: #{group_id}")
      rescue StandardError => e
        Rails.logger.warn("[WhatsAppWebhookService] Falha ao criar grupo padrão: #{e.class} - #{e.message}")
      end
    end

    # Broadcast atualização de conexão via Action Cable
    def broadcast_connection_update(instance, connection_status, event_data)
      payload = {
        type: 'connection_update',
        instance_id: instance.instance_id,
        status: connection_status,
        data: event_data,
        timestamp: Time.current.iso8601
      }

      ActionCable.server.broadcast("whatsapp_instance_#{instance.instance_id}", payload)
      ActionCable.server.broadcast("whatsapp_instance_#{instance.id}", payload)

      Rails.logger.info("[WhatsAppWebhookService] Connection update broadcasted for instance #{instance.instance_id}")
    end

    # Broadcast evento de logout via Action Cable
    def broadcast_logout_event(instance, logout_reason, timestamp)
      payload = {
        type: 'logout_instance',
        instance_id: instance.instance_id,
        reason: logout_reason,
        timestamp: timestamp ? Time.at(timestamp / 1000).iso8601 : Time.current.iso8601
      }
      ActionCable.server.broadcast("whatsapp_instance_#{instance.instance_id}", payload)
      ActionCable.server.broadcast("whatsapp_instance_#{instance.id}", payload)

      Rails.logger.info("[WhatsAppWebhookService] Logout event broadcasted for instance #{instance.instance_id}")
    end

    # Broadcast atualização de QR Code via Action Cable
    def broadcast_qrcode_update(instance, qr_code, _expires_in, _session)
      payload = {
        type: 'qrcode_updated',
        instance_id: instance.instance_id,
        qr_code: qr_code,
        timestamp: Time.current.iso8601
      }
      ActionCable.server.broadcast("whatsapp_instance_#{instance.instance_id}", payload)
      ActionCable.server.broadcast("whatsapp_instance_#{instance.id}", payload)

      Rails.logger.info("[WhatsAppWebhookService] QR Code update broadcasted for instance #{instance.instance_id}")
    end
  end
end
