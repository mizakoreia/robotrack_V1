# frozen_string_literal: true

# workspace-invitations §"Entidade Convite" e §"Token opaco" (tarefa 2.1 / D-INV-1).
#
# As garantias fortes vivem no BANCO (migration CreateInvitations): enum sem
# `owner`, `CHECK (email = lower(email))`, coerência de consumo, FK composta do
# criador. O model faz o que o banco não pode fazer sozinho: NORMALIZAR na
# escrita. O legado comparava com `request.auth.token.email.lower()` sem
# normalizar na leitura (D-INV-3), então o e-mail precisa nascer minúsculo — o
# CHECK apenas garante que ninguém contorne isso por fora.
class Invitation < ApplicationRecord
  include WorkspaceScoped

  # Prefixo próprio: barato de rotacionar e fácil de detectar numa varredura de
  # segredos. 32 bytes → 43 chars URL-safe → 256 bits de entropia (D-INV-1).
  TOKEN_PREFIX = 'rt_inv_'
  TOKEN_BYTES = 32
  TOKEN_FORMAT = /\Art_inv_[A-Za-z0-9_-]{43}\z/
  EMAIL_MAX = 254
  VALIDITY = 7.days

  belongs_to :created_by_person, class_name: 'Person', optional: true
  belongs_to :used_by_user, class_name: 'User', optional: true
  has_one :membership, dependent: :restrict_with_exception

  enum :role, { view: 'view', edit: 'edit' }

  before_validation :normalize_email
  before_validation :assign_token, on: :create
  before_validation :assign_expiry, on: :create

  validates :email, presence: true, length: { maximum: EMAIL_MAX }
  validates :role, presence: true
  validates :token, presence: true, format: { with: TOKEN_FORMAT }

  scope :pending, -> { where(used_at: nil) }

  def self.generate_token
    "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"
  end

  def used? = used_at.present?
  def expired? = expires_at.present? && expires_at <= Time.current

  # Estado apresentável: `used` vence `expired` (um convite consumido não vira
  # "expirado" quando a data passa — ele já produziu acesso).
  def status
    return 'used' if used?
    return 'expired' if expired?

    'pending'
  end

  # `j***@fabrica.com` (D-INV-6). Nunca o e-mail completo numa resposta pública:
  # o token é endereçável por quem o tiver, e vazar o destinatário entrega um
  # alvo de phishing. Revela domínio e primeira letra — o mínimo para o usuário
  # que autenticou com a conta errada saber qual conta usar.
  def email_masked
    local, domain = email.to_s.split('@', 2)
    return '***' if local.blank?

    "#{local[0]}***#{domain ? "@#{domain}" : ''}"
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def assign_token
    self.token ||= self.class.generate_token
  end

  def assign_expiry
    self.expires_at ||= Time.current + VALIDITY
  end
end
