# frozen_string_literal: true

# Rack::Attack — proteção de força bruta no login (identity-and-auth 4.3 / D4.7).
#
# Uma senha mínima de 6 caracteres sem travamento é brute-forceável; o throttle
# limita `POST /auth/v1/session` a 10 tentativas por 5 min, por par
# (IP, e-mail normalizado). O 429 volta antes de o endpoint verificar a senha. O
# bloqueio é POR e-mail (chave inclui o e-mail), não global: outro e-mail do
# mesmo IP passa. A igualdade do caminho negativo (hash bcrypt mesmo sem conta)
# fica no `Auth::SessionService`.
module Rack
  class Attack
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    LOGIN_PATH = '/auth/v1/session'

    # Tráfego local (dev/rspec) não é throttled — os specs de auth fazem vários
    # logins como 127.0.0.1 e não podem colidir com o limite. O spec de
    # rate-limit exercita o throttle com um IP não-local.
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

    self.throttled_responder = lambda do |req|
      match = req.env['rack.attack.match_data'] || {}
      retry_after = (match[:period] || 300).to_i
      headers = {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s,
        'RateLimit-Limit' => match[:limit].to_s,
        'RateLimit-Remaining' => '0'
      }
      [429, headers, [{ error: 'Muitas tentativas. Tente novamente mais tarde.' }.to_json]]
    end
  end
end
