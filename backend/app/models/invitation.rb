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

  # invite-by-code (design D1/D2): o código curto é a SEGUNDA representação do
  # MESMO convite. Crockford Base32 — 32 símbolos, exclui I/L/O/U (os ambíguos que
  # o §F.2 pediu). 8 chars → 32⁸ = 2⁴⁰; entropia baixa DE PROPÓSITO (digitável com
  # luva), segura só pela SOMA das defesas ativas + o vínculo de e-mail. Validade
  # PRÓPRIA de 48h, mais curta que os 7 dias do link.
  SHORT_CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
  SHORT_CODE_LEN = 8
  CODE_VALIDITY = 48.hours
  # Lockout por convite (design D7): após N falhas do PAR (código certo, e-mail
  # errado) contra a MESMA linha, o código trava. O link segue válido.
  CODE_MAX_ATTEMPTS = 5

  # O código em claro é TRANSIENTE: existe só no request de criação (para a entity
  # devolvê-lo uma vez) e nunca é persistido — a coluna guarda só o `code_hash`.
  attr_accessor :short_code

  belongs_to :created_by_person, class_name: 'Person', optional: true
  belongs_to :used_by_user, class_name: 'User', optional: true
  has_one :membership, dependent: :restrict_with_exception

  enum :role, { view: 'view', edit: 'edit' }

  before_validation :normalize_email
  before_validation :assign_token, on: :create
  before_validation :assign_expiry, on: :create
  before_validation :assign_short_code, on: :create

  validates :email, presence: true, length: { maximum: EMAIL_MAX }
  validates :role, presence: true
  validates :token, presence: true, format: { with: TOKEN_FORMAT }

  scope :pending, -> { where(used_at: nil) }

  def self.generate_token
    "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"
  end

  # Geração cripto sem viés de módulo: o alfabeto tem 32 símbolos (potência de 2),
  # então `SecureRandom.random_number(32)` é uniforme em 0..31 sem rejeição.
  def self.generate_short_code
    Array.new(SHORT_CODE_LEN) { SHORT_CODE_ALPHABET[SecureRandom.random_number(SHORT_CODE_ALPHABET.size)] }.join
  end

  # HMAC determinístico com pepper de servidor (D2). Determinístico para indexar e
  # achar a linha por igualdade; com pepper para não ser reconstruível offline se o
  # banco vazar. Normaliza ANTES do hash para casar a digitação do galpão.
  def self.code_hash_for(code)
    normalized = normalize_code(code)
    return nil if normalized.blank?

    OpenSSL::HMAC.hexdigest('SHA256', code_pepper, normalized)
  end

  # Tolerância de leitura (Crockford): maiúsculas, sem hífen/espaço, e os ambíguos
  # mapeados para o símbolo canônico (I/L→1, O→0). U está fora do alfabeto e não é
  # mapeado — é o símbolo que o Crockford descarta.
  def self.normalize_code(input)
    input.to_s.upcase.gsub(/[\s–—-]/, '').tr('ILO', '110')
  end

  # Pepper: credentials → ENV → default só em dev/test. O registro no `env_schema`
  # e a guarda de boot em produção/staging são endurecidos no G3.
  def self.code_pepper
    Rails.application.credentials.dig(:invitation_code_pepper).presence ||
      ENV['INVITATION_CODE_PEPPER'].presence ||
      (Rails.env.local? ? 'dev-insecure-invitation-code-pepper' : raise('INVITATION_CODE_PEPPER ausente'))
  end

  # Localiza a linha por código SEM workspace corrente, pela função SECURITY
  # DEFINER `invitation_by_code`. Recebe o código em CLARO; o HMAC é computado aqui
  # (o pepper nunca entra no banco). Devolve a Hash da linha ou `nil`. NÃO revela
  # estado nem decide nada — quem chama aplica a política anti-enumeração (par
  # e-mail primeiro; só então lockout/expiração).
  def self.row_by_code(code)
    hash = code_hash_for(code)
    return nil if hash.blank?

    conn = ActiveRecord::Base.connection
    conn.select_one(
      'SELECT id, workspace_id, email, role, expires_at, used_at, ' \
      "code_expires_at, code_locked_at FROM invitation_by_code(#{conn.quote(hash)})"
    )
  end

  def self.code_row_expired?(row)
    exp = row['code_expires_at']
    return false if exp.blank?

    time = exp.is_a?(Time) ? exp : Time.zone.parse(exp.to_s)
    time <= Time.current
  end

  # Registra UMA falha do par contra a linha, numa transação curta e PRÓPRIA (o
  # incremento persiste mesmo quando o request "falha" com resposta genérica).
  # Trava na Nª falha. `update_columns` (UPDATE direto) evita o commit-on-return e
  # não dispara callback. Idempotente contra linha já travada.
  def self.register_code_failure!(row, user_id: nil)
    Tenant.with(workspace_id: row['workspace_id'], user_id: user_id) do
      inv = lock('FOR UPDATE').find_by(id: row['id'])
      next if inv.nil? || inv.code_locked_at.present?

      attempts = inv.code_attempts.to_i + 1
      inv.update_columns(
        code_attempts: attempts,
        code_locked_at: (attempts >= CODE_MAX_ATTEMPTS ? Time.current : nil),
        updated_at: Time.current
      )
    end
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def used? = used_at.present?
  def expired? = expires_at.present? && expires_at <= Time.current
  def has_code? = code_hash.present?
  def code_expired? = code_expires_at.present? && code_expires_at <= Time.current
  def code_locked? = code_locked_at.present?

  # Estado apresentável do CÓDIGO (distinto do `status` do convite): `used` vence
  # `locked` vence `expired`. `nil` quando o convite não tem código (link puro).
  def code_status
    return nil unless has_code?
    return 'used' if used?
    return 'locked' if code_locked?
    return 'expired' if code_expired?

    'active'
  end

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

  # Todo convite nasce com código (decisão de execução: o código COEXISTE com o
  # link e é sempre gerado — resolve a subquestão menor de §F.1 sem um toggle na
  # UI). O claro fica no `short_code` transiente para a entity devolvê-lo uma vez;
  # a coluna guarda só o hash. Colisão de `code_hash` é tratada por retry no
  # CreateService (G2), relendo este callback com um convite novo.
  def assign_short_code
    return if code_hash.present?

    self.short_code ||= self.class.generate_short_code
    self.code_hash = self.class.code_hash_for(short_code)
    self.code_expires_at ||= Time.current + CODE_VALIDITY
  end
end
