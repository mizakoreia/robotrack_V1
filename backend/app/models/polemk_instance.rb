# frozen_string_literal: true

class PolemkInstance < ApplicationRecord
  has_many :polemk_webhooks, dependent: :destroy
  has_many :polemk_instance_groups, dependent: :destroy
  has_many :polemk_chat_messages, dependent: :destroy

  validates :display_name, presence: true
  validates :instance_name, presence: true
  validates :instance_id, presence: true, uniqueness: true
  validates :api_key, presence: true

  # Status de conexão válidos
  CONNECTION_STATUSES = %w[
    unknown
    connecting
    connected
    disconnected
    waiting_qr
  ].freeze

  validates :connection_status, inclusion: { in: CONNECTION_STATUSES }

  # Scopes para facilitar consultas
  scope :connected, -> { where(connection_status: 'connected') }
  scope :disconnected, -> { where(connection_status: 'disconnected') }
  scope :waiting_qr, -> { where(connection_status: 'waiting_qr') }

  def self.normalize_instance_name(display_name)
    return unless display_name.present?

    self.instance_name = I18n.transliterate(display_name)
                             .gsub(/[^\w\s-]/, '')
                             .gsub(/[\s-]+/, '_')
                             .upcase
  end

  # Verifica se a instância está conectada
  def connected?
    connection_status == 'connected'
  end

  # Verifica se está aguardando QR Code
  def waiting_qr?
    connection_status == 'waiting_qr'
  end

  # Verifica se o QR Code está expirado
  def qr_code_expired?
    return true if qr_expires_at.nil?

    Time.current > qr_expires_at
  end

  # Retorna o tempo restante do QR Code em segundos
  def qr_code_time_remaining
    return 0 if qr_expires_at.nil?

    remaining = (qr_expires_at - Time.current).to_i
    [remaining, 0].max
  end

  # Limpa dados sensíveis após logout
  def clear_connection_data
    update_columns(
      qr_code: nil,
      qr_expires_at: nil,
      qr_session: nil,
      last_qr_generated_at: nil,
      connection_data: nil
    )
  end

  def restart_instance
    EvolutionConnection.restart_instance
  end
end
