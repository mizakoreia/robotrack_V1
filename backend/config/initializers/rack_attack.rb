# frozen_string_literal: true

# Rack::Attack — proteção de força bruta no login (identity-and-auth 4.3 / D4.7)
# e nos endpoints de convite (workspace-invitations 6.1 / D-INV-8).
#
# Uma senha mínima de 6 caracteres sem travamento é brute-forceável; o throttle
# limita `POST /auth/v1/session` a 10 tentativas por 5 min, por par
# (IP, e-mail normalizado). O 429 volta antes de o endpoint verificar a senha. O
# bloqueio é POR e-mail (chave inclui o e-mail), não global: outro e-mail do
# mesmo IP passa. A igualdade do caminho negativo (hash bcrypt mesmo sem conta)
# fica no `Auth::SessionService`.
#
# Convites: o token tem 256 bits, então adivinhá-lo por força bruta é inviável
# por entropia — o teto existe porque o ACEITE é o endpoint mais CARO da
# aplicação (transação + lock pessimista + até três escritas) e o alvo natural de
# enumeração. Aceite: 10/10min por IP e por sessão. Pré-visualização (pública,
# pré-login): 20/10min por IP.
require_relative '../rate_limits'

module Rack
  class Attack
    # Store: Redis de CACHE (delivery-and-observability 7.1), para que o teto valha
    # entre PROCESSOS — com MemoryStore, N pumas dariam N vezes o limite. Cai para
    # memória quando não há Redis (test, dev sem serviço), sem derrubar o boot: um
    # rate limit degradado é melhor que uma app que não sobe.
    Rack::Attack.cache.store =
      begin
        if Rails.env.test? || ENV['REDIS_URL'].blank?
          ActiveSupport::Cache::MemoryStore.new
        else
          ActiveSupport::Cache::RedisCacheStore.new(url: EnvSchema.redis_for(:cache))
        end
      rescue StandardError => e
        Rails.logger.warn({ event: 'rack_attack_store_fallback', error: e.class.name }.to_json)
        ActiveSupport::Cache::MemoryStore.new
      end

    LOGIN_PATH = '/auth/v1/session'
    ACCEPT_PATH = %r{\A/api/v1/invitations/[^/]+/accept/?\z}
    PREVIEW_PATH = %r{\A/api/v1/invitations/[^/]+/?\z}
    INVITE_TOKEN_IN_PATH = %r{/api/v1/invitations/([^/]+)}

    # Tráfego local (dev/rspec) não é throttled — os specs de auth fazem vários
    # logins como 127.0.0.1 e não podem colidir com o limite. Os specs de
    # rate-limit exercitam o throttle com um IP não-local.
    safelist('allow-localhost') do |req|
      ['127.0.0.1', '::1'].include?(req.ip)
    end

    # Throttle de login por (IP, e-mail normalizado).
    throttle('login/ip-email', limit: 10, period: 5.minutes) do |req|
      if req.post? && req.path == LOGIN_PATH
        email = req.params['email'].to_s.downcase.gsub(/\s+/, '')
        "#{req.ip}:#{email}" if email.present?
      end
    end

    # Aceite de convite: por IP.
    throttle('invitations/accept-ip', limit: 10, period: 10.minutes) do |req|
      req.ip if req.post? && ACCEPT_PATH.match?(req.path)
    end

    # Aceite de convite: por SESSÃO. A chave é o hash do bearer, não o `sub` do
    # JWT: decodificar aqui exigiria consultar o denylist (uma ida ao banco) a
    # cada requisição, e o ponto do teto é justamente NÃO tocar o banco. Um token
    # por sessão, então o hash identifica a sessão que insiste.
    throttle('invitations/accept-session', limit: 10, period: 10.minutes) do |req|
      if req.post? && ACCEPT_PATH.match?(req.path)
        bearer = req.get_header('HTTP_AUTHORIZATION').to_s.split(' ').last
        "sess:#{Digest::SHA256.hexdigest(bearer)[0, 16]}" if bearer.present?
      end
    end

    # Pré-visualização pública: teto mais apertado, só por IP (não há sessão).
    throttle('invitations/preview-ip', limit: 20, period: 10.minutes) do |req|
      req.ip if req.get? && PREVIEW_PATH.match?(req.path)
    end

    # ── Tetos por CLASSE de domínio (7.2/7.3), por minuto, por identidade ──────
    # Um throttle por classe; o discriminador devolve a chave só quando a
    # requisição pertence àquela classe, senão a ignora. `limit` é lido do ENV a
    # cada request (barato) para o teto ser configurável sem redeploy.
    %i[read write robot_batch advance report].each do |klass|
      throttle("domain/#{klass}", limit: ->(_req) { RateLimits.limit(klass) }, period: 60) do |req|
        next unless RateLimits.classify(req.request_method, req.path) == klass

        bearer = req.get_header('HTTP_AUTHORIZATION').to_s.split(' ').last
        RateLimits.identity(bearer, req.ip)
      end
    end

    self.throttled_responder = lambda do |req|
      match = req.env['rack.attack.match_data'] || {}
      retry_after = (match[:period] || 300).to_i

      # Log estruturado do bloqueio. O token é CREDENCIAL: nunca em claro, nem
      # aqui, nem na linha de request (ver initializers/invitation_log_scrubber).
      # 12 chars de SHA-256 bastam para correlacionar tentativas do mesmo token
      # sem permitir reconstruí-lo.
      token = req.path[INVITE_TOKEN_IN_PATH, 1]
      Rails.logger.warn(
        {
          event: 'rate_limit_blocked',
          matched: req.env['rack.attack.matched'],
          ip: req.ip,
          token_sha256: token ? Digest::SHA256.hexdigest(token)[0, 12] : nil
        }.compact.to_json
      )

      headers = {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s,
        'RateLimit-Limit' => match[:limit].to_s,
        'RateLimit-Remaining' => '0'
      }
      body = I18n.t('errors.rate_limited', locale: :'pt-BR',
                    default: 'Muitas tentativas. Tente novamente mais tarde.')
      [429, headers, [{ error: body }.to_json]]
    end
  end
end
