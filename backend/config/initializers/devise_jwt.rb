# frozen_string_literal: true

require 'warden/jwt_auth'

Rails.application.config.after_initialize do
  Warden::JWTAuth.configure do |config|
    config.secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] || Rails.application.credentials.secret_key_base || (Rails.application.respond_to?(:secret_key_base) ? Rails.application.secret_key_base : nil)
    config.algorithm = 'HS256'
    config.dispatch_requests = []
    config.revocation_requests = []
    config.mappings = { user: User }
  end
end
