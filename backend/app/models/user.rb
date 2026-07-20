# frozen_string_literal: true

# Modelo de usuário (identity-and-auth): senha Devise + Google OAuth.
# `encrypted_password` para login local; `provider`/`provider_uid` para Google.
class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :omniauthable, :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist,
         omniauth_providers: %i[google_oauth2]
  # Associations
  # `user_type` é herança do domínio de cobrança do template e deixou de ser
  # obrigatória (identity-and-auth 1.3 relaxou o NOT NULL/FK): o cadastro por
  # senha não a preenche. O gate `User#og?` sobre UserType segue existindo até
  # `authorization-policies` substituí-lo por Membership.role.
  belongs_to :user_type, optional: true
  has_rich_text :biography

  # workspace-tenancy: cada usuário é dono de no máximo um workspace (§1.1) e
  # pode ser uma Person (via user_id) em vários workspaces.
  has_one :owned_workspace, class_name: 'Workspace', foreign_key: 'owner_user_id',
                            inverse_of: :owner, dependent: :restrict_with_exception
  has_many :people, dependent: :nullify
  has_many :memberships, dependent: :restrict_with_exception

  # Validations
  # Nome normalizado (strip + colapso de espaços) antes de validar; o mínimo de
  # 2 caracteres não-brancos é reforçado por CHECK no banco (D4.6).
  before_validation :normalize_name
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  # `user_type_id` deixou de ser NOT NULL (identity-and-auth 1.3); o cadastro por
  # senha não o preenche. Sem validação de presença.

  # E-mail é a chave de identidade (D4.5): sempre presente e único.
  validates :email, presence: true

  # Senha mínima de 6 (§3.1). Sem o módulo :validatable, a regra vive aqui,
  # aplicada só quando a senha está sendo definida (cadastro/troca). Usuário
  # só-Google não define senha e o CHECK de credencial no banco garante que ele
  # tenha `provider`.
  validates :password, length: { in: Devise.password_length }, if: -> { password.present? }

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

  validates :provider, inclusion: { in: %w[google_oauth2 google facebook email whatsapp] }, allow_nil: true
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

  # A resolução de identidade do Google vive em `Auth::GoogleOauthService`
  # (identity-and-auth 3.2): vínculo por e-mail VERIFICADO, sem duplicar, com
  # `provider = 'google_oauth2'`. O antigo `find_or_create_by_oauth` (provider
  # 'google', sem checar verificação) foi removido.

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

  # Acessores voláteis usados na emissão do JWT (setados pelo TokenService antes
  # de `jwt_payload`). Não usamos o `remember_me` do Devise — não incluímos o
  # módulo `:rememberable` (sessão por cookie), então o accessor é nosso.
  # `jwt_iat_origin`: instante do login original, propagado nas renovações (D4.3).
  attr_accessor :jwt_remember_me, :jwt_iat_origin

  # Payload do JWT (D4.2/D4.3). Carimba `exp` conforme "manter conectado" e
  # propaga `iat_origin`. É chamado DIRETAMENTE pelo `Auth::TokenService` (não
  # pelo dispatch do Warden, que injetaria `scp`/`aud`), para que o payload tenha
  # exatamente `sub, jti, exp, iat, iat_origin` — o token identifica, não autoriza
  # (sem `workspace_id`/`role`; a autorização é de authorization-policies + RLS).
  def jwt_payload
    now = Time.now.to_i
    remember = ActiveModel::Type::Boolean.new.cast(jwt_remember_me)
    ttl = remember ? Auth::TokenService.remember_ttl_seconds : Auth::TokenService.session_ttl_seconds
    {
      'iat' => now,
      'exp' => now + ttl,
      'iat_origin' => (jwt_iat_origin || now)
    }
  end

  private

  # "  Ana   Souza  " → "Ana Souza". Roda antes das validações; um nome só de
  # espaços vira "" e a validação de presença o recusa (D4.6).
  def normalize_name
    self.name = name.strip.gsub(/\s+/, ' ') if name.present?
  end

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
