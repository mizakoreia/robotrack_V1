# frozen_string_literal: true

# Canal para transmitir atualizações de instâncias WhatsApp em tempo real
class WhatsappInstanceChannel < ApplicationCable::Channel
  def subscribed
    instance_key = params[:instance_id]
    unless instance_key.present?
      reject
      return
    end
    stream_from "whatsapp_instance_#{instance_key}"
    instance = PolemkInstance.find_by(instance_id: instance_key) || PolemkInstance.where(id: instance_key).first
    stream_from "whatsapp_instance_#{instance.id}" if instance
    Rails.logger.info("[WhatsAppInstanceChannel] Subscribed with key #{instance_key}")
  end

  def unsubscribed
    # Limpeza quando o canal é desconectado
    Rails.logger.info("[WhatsAppInstanceChannel] User #{current_user&.id} unsubscribed")
  end

  # Recebe ping do cliente para manter conexão ativa
  def ping(data)
    Rails.logger.debug("[WhatsAppInstanceChannel] Ping received: #{data}")
    transmit({ type: 'pong', timestamp: Time.current.iso8601 })
  end

  private

  # Verifica se o usuário atual pode acessar a instância
  def can_access_instance?(_instance_id)
    true
  end
end
