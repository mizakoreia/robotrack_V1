# frozen_string_literal: true

# Modelo para registrar tentativas de login (audit log)
# Usado para segurança, análise e detecção de fraudes
class LoginAttempt < ApplicationRecord
  # Associations (opcional - não deleta se usuário for deletado)
  belongs_to :user, optional: true

  # Validations
  validates :identifier, presence: true
  validates :method, inclusion: { in: %w[email whatsapp google facebook] }
  validates :ip_address, presence: true
  validates :success, inclusion: { in: [true, false] }

  # Scopes
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :by_method, ->(method) { where(method: method) }
  scope :by_identifier, ->(identifier) { where(identifier: identifier) }
  scope :by_ip, ->(ip) { where(ip_address: ip) }
  scope :recent, -> { order(created_at: :desc) }
  scope :last_hour, -> { where('created_at > ?', 1.hour.ago) }
  scope :last_day, -> { where('created_at > ?', 1.day.ago) }
  scope :last_week, -> { where('created_at > ?', 1.week.ago) }

  # Métodos de classe
  def self.log_attempt!(identifier, method, ip_address, user_agent, success, user = nil, error_reason = nil)
    create!(
      identifier: normalize_identifier(identifier, method),
      method: method,
      ip_address: ip_address,
      user_agent: user_agent,
      success: success,
      user: user,
      error_reason: error_reason
    )
  end

  def self.failed_attempts_count(identifier, time_range = 1.hour)
    failed
      .by_identifier(identifier)
      .where('created_at > ?', time_range.ago)
      .count
  end

  def self.failed_attempts_by_ip(ip_address, time_range = 1.hour)
    failed
      .by_ip(ip_address)
      .where('created_at > ?', time_range.ago)
  end

  def self.suspicious_activity?(identifier, ip_address = nil)
    # Verifica múltiplas falhas para o mesmo identificador
    identifier_failures = failed_attempts_count(identifier, 15.minutes)
    return true if identifier_failures >= 5

    # Verifica múltiplas tentativas do mesmo IP (se fornecido)
    if ip_address.present?
      ip_failures = failed_attempts_by_ip(ip_address, 15.minutes).count
      return true if ip_failures >= 10

      # Verifica tentativas de múltiplos identificadores do mesmo IP
      unique_identifiers = failed_attempts_by_ip(ip_address, 15.minutes).distinct.count(:identifier)
      return true if unique_identifiers >= 5
    end

    false
  end

  def self.brute_force_detected?(identifier, _ip_address = nil)
    # Detecção de força bruta: muitas tentativas em curto período
    recent_attempts = where('created_at > ?', 5.minutes.ago)
                      .by_identifier(identifier)
                      .count

    return true if recent_attempts >= 10

    # Verifica padrões de tentativa rápida
    attempts = where('created_at > ?', 1.minute.ago)
               .by_identifier(identifier)
               .order(:created_at)

    return false if attempts.count < 5

    # Verifica se as tentativas foram muito rápidas (menos de 2 segundos entre elas)
    attempts.each_cons(2) do |prev, curr|
      time_diff = curr.created_at - prev.created_at
      return true if time_diff < 2.seconds
    end

    false
  end

  def self.login_success_rate(time_range = 1.day)
    attempts = where('created_at > ?', time_range.ago)
    total = attempts.count
    successful = attempts.successful.count

    return 0 if total.zero?

    (successful.to_f / total * 100).round(2)
  end

  def self.method_success_rates(time_range = 1.day)
    %w[email whatsapp google facebook].map do |method|
      attempts = where('created_at > ?', time_range.ago).by_method(method)
      total = attempts.count
      successful = attempts.successful.count

      success_rate = total.zero? ? 0 : (successful.to_f / total * 100).round(2)

      {
        method: method,
        total_attempts: total,
        successful_attempts: successful,
        success_rate: success_rate
      }
    end
  end

  def self.top_failed_identifiers(limit = 10, time_range = 1.day)
    failed
      .where('created_at > ?', time_range.ago)
      .group(:identifier)
      .order('count_all DESC')
      .limit(limit)
      .count
  end

  def self.suspicious_ips(time_range = 1.day, failure_threshold = 20)
    failed
      .where('created_at > ?', time_range.ago)
      .group(:ip_address)
      .having('count_all >= ?', failure_threshold)
      .order('count_all DESC')
      .count
      .keys
  end

  # Métodos de instância
  def successful?
    success == true
  end

  def failed?
    success == false
  end

  def social_method?
    %w[google facebook].include?(method)
  end

  def code_method?
    %w[email whatsapp].include?(method)
  end

  def formatted_ip_address
    return nil if ip_address.blank?

    if ip_address.ipv4?
    end
    ip_address.to_s
  end

  def user_agent_info
    return {} if user_agent.blank?

    # Parse básico do user agent (pode usar gem como 'browser' para mais detalhes)
    {
      browser: extract_browser,
      os: extract_os,
      device: extract_device
    }
  end

  def to_security_log
    {
      id: id,
      timestamp: created_at.iso8601,
      identifier: identifier,
      method: method,
      ip_address: formatted_ip_address,
      success: success,
      error_reason: error_reason,
      user_agent: user_agent_info,
      user_id: user_id
    }
  end

  def location_info
    return {} if ip_address.blank?

    # Placeholder para futura integração com serviço de geolocalização
    # Ex: MaxMind GeoIP, IPStack, etc.
    {}
  end

  private

  def self.normalize_identifier(identifier, method)
    return identifier if identifier.blank?

    case method
    when 'email'
      identifier.downcase.strip
    when 'whatsapp'
      # Normaliza telefone
      identifier.gsub(/[^0-9]/, '')

    else
      identifier.strip
    end
  end

  def extract_browser
    return 'Unknown' if user_agent.blank?

    case user_agent
    when /Chrome/
      'Chrome'
    when /Firefox/
      'Firefox'
    when /Safari/
      'Safari'
    when /Edge/
      'Edge'
    when /Opera/
      'Opera'
    else
      'Other'
    end
  end

  def extract_os
    return 'Unknown' if user_agent.blank?

    case user_agent
    when /Windows NT/
      'Windows'
    when /Mac OS X/
      'macOS'
    when /Linux/
      'Linux'
    when /Android/
      'Android'
    when /iPhone|iPad/
      'iOS'
    else
      'Other'
    end
  end

  def extract_device
    return 'Unknown' if user_agent.blank?

    case user_agent
    when /Mobile/
      'Mobile'
    when /Tablet|iPad/
      'Tablet'
    else
      'Desktop'
    end
  end
end
