# frozen_string_literal: true

class PolemkWebhook < ApplicationRecord
  belongs_to :polemk_instance

  validates :url, presence: true
  validates :polemk_instance_id, presence: true
  validates :url, presence: true
  validates :enabled, presence: true
  validates :webhook_by_events, presence: true
  validates :webhook_base_64, presence: true
  validates :event, presence: true
  validates :raw_response, presence: true

  def display_name
    case event
    when 'SEND_MESSAGE' then 'Envio de mensagens'
    when 'MESSAGES_UPSERT' then 'Recebimento de mensagens'
    when 'MESSAGES_UPDATE' then 'Confirmação de leitura'
    when 'CONNECTION_UPDATE' then 'Atualização de conexão'
    when 'LOGOUT_INSTANCE' then 'Logout da instância'
    when 'QRCODE_UPDATED' then 'Atualização de QR Code'
    else
      event&.humanize || 'Webhook'
    end
  end

  def extract_base_url
    events = %w[send-message messages-upsert messages-update connection-update logout-instance qrcode-updated]
    return '' if url.blank?

    begin
      # Remove espaços em branco e normaliza a URL
      clean_url = url.strip
      return '' if clean_url.blank?

      uri = URI.parse(clean_url)
      clean_path = uri.path || ''

      events.each do |event|
        suffix = "/#{event}"
        if clean_path.downcase.end_with?(suffix)
          clean_path = clean_path[0...-suffix.length]
          break
        end
      end

      # Garante que o path não seja vazio
      clean_path = '/' if clean_path.blank?

      "#{uri.scheme}://#{uri.host}#{uri.port && uri.port != 80 && uri.port != 443 ? ":#{uri.port}" : ''}#{clean_path}"
    rescue URI::InvalidURIError => e
      Rails.logger.error("URL inválida no webhook #{id}: #{url} - Erro: #{e.message}")
      ''
    rescue StandardError => e
      Rails.logger.error("Erro ao processar URL do webhook #{id}: #{e.message}")
      ''
    end
  end
end
