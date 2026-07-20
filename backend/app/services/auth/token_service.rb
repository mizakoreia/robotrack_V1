# frozen_string_literal: true

require 'jwt'

module Auth
  # Emissão, verificação e revogação de JWT (identity-and-auth).
  #
  # O payload é MÍNIMO e controlado: `sub, jti, exp, iat, iat_origin` — o token
  # identifica, não autoriza (spec `identity-and-auth` §"O token identifica, não
  # autoriza"). Por isso NÃO usamos o dispatch automático do Warden/devise-jwt,
  # que injetaria `scp`/`aud`: encodamos chamando `User#jwt_payload` direto.
  #
  # A revogação é honesta: usa os métodos da própria estratégia
  # `Devise::JWT::RevocationStrategies::Denylist` (via `JwtDenylist`). Logout
  # grava o `jti`; toda verificação recusa um `jti` presente no denylist. Um teste
  # de denylist que passe aqui só passa porque a revogação de fato funciona.
  class TokenService
    ALGORITHM = 'HS256'

    class RevokedToken < StandardError; end

    def self.remember_ttl_seconds
      ENV.fetch('JWT_TTL_REMEMBER_DAYS', '30').to_i.days.to_i
    end

    def self.session_ttl_seconds
      ENV.fetch('JWT_TTL_SESSION_HOURS', '12').to_i.hours.to_i
    end

    def self.secret
      ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] ||
        Rails.application.credentials.secret_key_base ||
        Rails.application.secret_key_base
    end

    # Emite um token para `user`. `iat_origin` nil = login inicial (vira `iat`);
    # nas renovações, o `iat_origin` do token anterior é propagado. Devolve
    # `[token, payload]`.
    def self.issue(user, remember_me:, iat_origin: nil)
      user.jwt_remember_me = remember_me
      user.jwt_iat_origin = iat_origin
      payload = user.jwt_payload.merge(
        'sub' => user.id.to_s,
        'jti' => SecureRandom.uuid
      )
      [JWT.encode(payload, secret, ALGORITHM), payload]
    end

    # Decodifica e VALIDA: assinatura, expiração (opcional) e denylist. Levanta
    # `JWT::ExpiredSignature`, `JWT::DecodeError` ou `RevokedToken`.
    def self.decode(token, verify_exp: true)
      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_expiration: verify_exp)
      raise RevokedToken if JwtDenylist.jwt_revoked?(payload, nil)

      payload
    end

    # Grava o `jti` no denylist. Idempotente (find_or_create).
    def self.revoke(payload)
      JwtDenylist.revoke_jwt(payload, nil)
    end

    # --- Instância (compat com chamadores legados de OAuth, removidos em G3) ---
    def initialize(user)
      @user = user
    end

    def generate_tokens
      token, = self.class.issue(@user, remember_me: false)
      { token: token }
    end

    def decode_token(token, verify_exp: true)
      self.class.decode(token, verify_exp: verify_exp)
    end
  end
end
