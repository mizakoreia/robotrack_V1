# frozen_string_literal: true

# Configure Rack Attack
module Rack
  class Attack
    # Use Rails cache store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    # Allow all local traffic
    safelist('allow-localhost') do |req|
      ['127.0.0.1', '::1'].include?(req.ip)
    end

    # Throttle requests to 60 per minute per IP
    throttle('req/ip', limit: 60, period: 1.minute, &:ip)

    # Throttle login attempts to 5 per minute per IP
    throttle('logins/ip', limit: 5, period: 1.minute) do |req|
      req.ip if req.path == '/api/v1/auth/login' && req.post?
    end

    # Throttle login attempts to 5 per minute per email
    throttle('logins/email', limit: 5, period: 1.minute) do |req|
      req.params['email'].to_s.downcase.gsub(/\s+/, '') if req.path == '/api/v1/auth/login' && req.post?
    end

    # Custom response for throttled requests
    self.throttled_response = lambda do |env|
      now = Time.now
      match_data = env['rack.attack.match_data']

      headers = {
        'Content-Type' => 'application/json',
        'X-RateLimit-Limit' => match_data[:limit].to_s,
        'X-RateLimit-Remaining' => '0',
        'X-RateLimit-Reset' => (now + (match_data[:period] - now.to_i % match_data[:period])).to_s
      }

      [429, headers, [{ error: 'Rate limit exceeded. Try again later.' }.to_json]]
    end
  end
end
