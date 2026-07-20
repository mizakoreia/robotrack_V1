# frozen_string_literal: true

# Modelo de usuário para o sistema de Magic Login
# Suporta autenticação via código (email/WhatsApp) e OAuth social
class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: %i[google_oauth2 facebook]
  # Associations
  belongs_to :user_type
  has_rich_text :biography

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :user_type_id, presence: true

  # Email ou telefone deve estar presente
  validates :email, presence: true, unless: -> { phone.present? }
  validates :phone, presence: true, unless: -> { email.present? }

  # Validações específicas por campo
  validates :email,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false },
            allow_blank: true

  validates :phone,
            format: { with: /\A[0-9]{10,15}\z/ },
            uniqueness: true,
            allow_blank: true

  # Documento e endereço
  validates :cpf_cnpj,
            format: { with: /\A(?:\d{11}|\d{14})\z/ },
            allow_blank: true,
            if: -> { self.class.column_names.include?('cpf_cnpj') }
  validates :cep,
            format: { with: /\A\d{8}\z/ },
            allow_blank: true,
            if: -> { self.class.column_names.include?('cep') }
  validates :state,
            format: { with: /\A[A-Z]{2}\z/ },
            allow_blank: true,
            if: -> { self.class.column_names.include?('state') }

  validates :provider, inclusion: { in: %w[email whatsapp google facebook] }, allow_nil: true
  validates :provider_uid, uniqueness: { scope: :provider }, allow_nil: true

  # Callbacks
  before_save :normalize_email, if: :email_changed?
  before_save :normalize_phone, if: :phone_changed?
  before_save :normalize_cpf_cnpj, if: -> { respond_to?(:cpf_cnpj_changed?) && cpf_cnpj_changed? }
  before_save :normalize_cep, if: -> { respond_to?(:cep_changed?) && cep_changed? }
  before_save :normalize_state, if: -> { respond_to?(:state_changed?) && state_changed? }

  # Scopes
  scope :by_email, ->(email) { where(email: email.downcase) }
  scope :by_phone, ->(phone) { where(phone: normalize_phone_number(phone)) }
  scope :by_provider, ->(provider, uid) { where(provider: provider, provider_uid: uid) }
  scope :active, -> { where.not(last_login_at: nil) }

  # Métodos de classe
  def self.find_or_create_by_email(email, name = nil)
    user = find_by(email: email.downcase)

    if user.nil?
      client_type = UserType.find_by(name: 'client')
      user = create!(
        email: email,
        name: name || email.split('@').first,
        user_type: client_type,
        provider: 'email'
      )
    end

    user
  end

  def self.find_or_create_by_phone(phone, name = nil)
    normalized_phone = normalize_phone_number(phone)
    user = find_by(phone: normalized_phone)

    if user.nil?
      client_type = UserType.find_by(name: 'client')
      user = create!(
        phone: normalized_phone,
        name: name || "User #{normalized_phone[-4, 4]}",
        user_type: client_type,
        provider: 'whatsapp'
      )
    end

    user
  end

  def self.find_or_create_by_oauth(provider, uid, info)
    user = find_by(provider: provider, provider_uid: uid)

    if user.nil?
      # Tentar encontrar por email primeiro
      user = find_by(email: info[:email].downcase) if info[:email].present?

      if user.nil?
        client_type = UserType.find_by(name: 'client')
        user = create!(
          email: info[:email],
          name: info[:name] || "#{provider}_user",
          avatar_url: info[:image],
          user_type: client_type,
          provider: provider,
          provider_uid: uid
        )
      else
        # Atualizar provider info se usuário já existe
        user.update!(
          provider: provider,
          provider_uid: uid,
          avatar_url: info[:image] || user.avatar_url
        )
      end
    end

    user
  end

  # Métodos de instância
  def og?
    user_type&.name.to_s.downcase == 'og'
  end

  def client?
    user_type&.name.to_s.downcase == 'client'
  end

  def display_name
    name.presence || email&.split('@')&.first || phone&.slice(-4, 4)
  end

  def display_identifier
    email.presence || phone.presence || "#{provider}:#{provider_uid}"
  end

  def update_login_stats!
    update!(
      last_login_at: Time.current,
      login_count: login_count + 1
    )
  end

  def jwt_subject
    id
  end

  private

  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  def normalize_phone
    self.phone = self.class.normalize_phone_number(phone) if phone.present?
  end

  def normalize_cpf_cnpj
    self.cpf_cnpj = cpf_cnpj.to_s.gsub(/[^0-9]/, '') if cpf_cnpj.present?
  end

  def normalize_cep
    self.cep = cep.to_s.gsub(/[^0-9]/, '') if cep.present?
  end

  def normalize_state
    self.state = state.to_s.strip.upcase if state.present?
  end

  def self.normalize_phone_number(phone)
    # Normaliza para somente dígitos (sem '+') para compatibilidade com dados existentes
    phone.to_s.gsub(/[^0-9]/, '')
  end
end
