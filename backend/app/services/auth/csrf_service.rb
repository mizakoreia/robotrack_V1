# frozen_string_literal: true

require 'openssl'

module Auth
  class CsrfService
    def initialize(user)
      @user = user
      @secret = ENV['CSRF_SECRET'] || Rails.application.credentials.secret_key_base || 'change-me-csrf'
    end

    def generate
      ts = Time.current.to_i
      data = "#{@user.id}:#{ts}"
      mac = OpenSSL::HMAC.hexdigest('SHA256', @secret, data)
      "#{ts}.#{mac}"
    end

    def valid?(token, ttl: 7200)
      return false if token.to_s.strip.empty?

      parts = token.split('.')
      return false unless parts.size == 2

      ts = parts[0].to_i
      return false if ts <= 0
      return false if Time.at(ts) < ttl.seconds.ago

      data = "#{@user.id}:#{ts}"
      mac = OpenSSL::HMAC.hexdigest('SHA256', @secret, data)
      ActiveSupport::SecurityUtils.secure_compare(mac, parts[1])
    end
  end
end
