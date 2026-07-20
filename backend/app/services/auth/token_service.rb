# frozen_string_literal: true

require 'jwt'

module Auth
  class TokenService
    ACCESS_TTL = ENV.fetch('JWT_EXPIRATION_TIME_MINUTES', '240').to_i.minutes
    REFRESH_TTL = ENV.fetch('JWT_REFRESH_EXPIRATION_DAYS', '30').to_i.days

    def initialize(user)
      @user = user
      @algorithm = 'HS256'
      @secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] || Rails.application.credentials.secret_key_base || (Rails.application.respond_to?(:secret_key_base) ? Rails.application.secret_key_base : nil) || 'change-me-dev-secret'
    end

    def generate_tokens
      {
        token: generate_access_token,
        refresh_token: generate_refresh_token
      }
    end

    def decode_token(token, verify_exp: true)
      options = { algorithm: @algorithm }
      options[:verify_expiration] = verify_exp
      payload, = JWT.decode(token, @secret, true, options)
      if ActiveRecord::Base.connection.table_exists?('jwt_denylist')
        jti = payload['jti']
        if jti && ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM jwt_denylist WHERE jti='#{jti}'").to_i.positive?
          raise JWT::DecodeError
        end
      end
      payload
    rescue JWT::ExpiredSignature
      raise JWT::ExpiredSignature
    rescue JWT::DecodeError
      raise JWT::DecodeError
    end

    private

    def generate_access_token
      if defined?(Warden::JWTAuth::UserEncoder) && @user
        token, _payload = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil)
        return token
      end
      payload = {
        sub: @user.id,
        type: 'user',
        exp: ACCESS_TTL.from_now.to_i,
        iat: Time.current.to_i
      }
      JWT.encode(payload, @secret, @algorithm)
    end

    def generate_refresh_token
      payload = {
        sub: @user.id,
        type: 'refresh',
        exp: REFRESH_TTL.from_now.to_i,
        iat: Time.current.to_i,
        jti: SecureRandom.uuid
      }
      JWT.encode(payload, @secret, @algorithm)
    end
  end
end
