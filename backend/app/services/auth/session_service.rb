# frozen_string_literal: true

require 'bcrypt'

module Auth
  # Ciclo de vida da sessão por senha (identity-and-auth 2.4).
  #
  # login  — verifica e-mail+senha, emite JWT. Caminho negativo idêntico para
  #          senha errada e e-mail inexistente, e SEMPRE roda o hash bcrypt para
  #          não vazar a existência da conta pelo tempo de resposta (D4.7).
  # logout — grava o `jti` do token no denylist (revoga só aquele token, D4.1).
  # renew  — rotaciona o `jti` (grava o antigo, emite um novo), preservando
  #          `iat_origin`, e RECUSA depois do teto absoluto `iat_origin + 2×TTL`
  #          (D4.3): sem o teto, renovar em loop torna uma sessão de 12h eterna.
  #
  # Resultado é um Hash simples que o endpoint Grape transforma no envelope
  # `data`/`error` e no header `Authorization`.
  class SessionService
    INVALID_CREDENTIALS = 'E-mail ou senha inválidos.'

    # Digest bcrypt fixo para queimar tempo no caminho negativo (conta inexistente).
    DUMMY_DIGEST = ::BCrypt::Password.create('identity-and-auth::timing-equalizer').to_s.freeze

    def self.login(email:, password:, remember_me: false)
      user = User.find_by(email: email.to_s.downcase.strip)

      if user&.valid_password?(password)
        token, = TokenService.issue(user, remember_me: remember_me)
        { ok: true, status: 200, token: token, user: user }
      else
        # Queima o mesmo custo de bcrypt mesmo sem conta, e para conta só-Google
        # (encrypted_password vazio) o valid_password? já devolve false.
        User.new(encrypted_password: DUMMY_DIGEST).valid_password?(password.to_s) unless user
        { ok: false, status: 401, error: INVALID_CREDENTIALS }
      end
    end

    def self.logout(token:)
      payload = TokenService.decode(token, verify_exp: false)
      TokenService.revoke(payload)
      { ok: true, status: 204 }
    rescue JWT::DecodeError, TokenService::RevokedToken
      # Token inválido/já revogado: idempotente, nada a revogar.
      { ok: true, status: 204 }
    end

    def self.renew(token:)
      payload = TokenService.decode(token, verify_exp: true) # recusa expirado E revogado
      return { ok: false, status: 401, error: 'Sessão expirada.' } if beyond_cap?(payload)

      user = User.find_by(id: payload['sub'])
      return { ok: false, status: 401, error: 'Sessão inválida.' } unless user

      TokenService.revoke(payload) # mata o token antigo (rotação de jti)
      new_token, = TokenService.issue(
        user,
        remember_me: remember?(payload),
        iat_origin: payload['iat_origin']
      )
      { ok: true, status: 200, token: new_token, user: user }
    rescue JWT::ExpiredSignature, JWT::DecodeError, TokenService::RevokedToken
      { ok: false, status: 401, error: 'Sessão expirada.' }
    end

    # TTL do próprio token (exp - iat); o teto é iat_origin + 2×TTL.
    def self.beyond_cap?(payload)
      ttl = payload['exp'].to_i - payload['iat'].to_i
      cap = payload['iat_origin'].to_i + (2 * ttl)
      Time.now.to_i > cap
    end

    # Deriva remember-ness do TTL do token: um token de "manter conectado" tem TTL
    # maior que o de sessão curta.
    def self.remember?(payload)
      ttl = payload['exp'].to_i - payload['iat'].to_i
      ttl > TokenService.session_ttl_seconds
    end
  end
end
