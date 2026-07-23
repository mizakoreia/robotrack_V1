# frozen_string_literal: true

require_relative 'env_schema'

# Rate limit de domínio (delivery-and-observability 7.2/7.3). Limites por CLASSE de
# rota via ENV, e chave por IDENTIDADE (user_id do JWT, sem tocar o banco) caindo
# para IP. Assim 8 engenheiros no mesmo NAT do galpão não se bloqueiam quando um
# excede o limite, e a 11ª criação em lote no minuto responde 429 enquanto as
# leituras do mesmo usuário seguem 2xx.
module RateLimits
  module_function

  def limit(klass)
    EnvSchema.fetch("RATE_LIMIT_#{klass.to_s.upcase}").to_i
  end

  # Classifica a requisição numa classe de teto (ou nil = sem teto de domínio).
  def classify(method, path)
    return nil unless path.start_with?('/api/')

    case
    when path.match?(%r{\A/api/v1/robots/batch}) then :robot_batch
    when path.match?(%r{/advances?(/|\z)}) then :advance
    when path.match?(%r{\A/api/v1/reports}) then :report
    when method == 'GET' then :read
    else :write
    end
  end

  # Identidade para a chave do throttle: `sub` do JWT (verificado por assinatura,
  # SEM consulta a `users` nem checagem de denylist — o ponto do teto é não tocar o
  # banco). Cai para o IP quando não há bearer decodificável.
  def identity(bearer, ip)
    sub = jwt_sub(bearer)
    sub ? "user:#{sub}" : "ip:#{ip}"
  end

  def jwt_sub(bearer)
    return nil if bearer.blank?

    secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['SECRET_KEY_BASE']
    return nil if secret.blank?

    payload, = JWT.decode(bearer, secret, true, algorithm: 'HS256', verify_expiration: false)
    payload['sub']
  rescue StandardError
    nil
  end
end
