# frozen_string_literal: true

require 'devise/orm/active_record'
Devise.setup do |config|
  config.mailer_sender = ENV.fetch('DEVISE_MAILER_FROM', 'no-reply@robotrack.local')
  config.secret_key = Rails.application.credentials.secret_key_base
  config.omniauth_path_prefix = '/users/auth'
  OmniAuth.config.path_prefix = '/users/auth'

  config.jwt do |jwt|
    jwt.secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] || Rails.application.credentials.secret_key_base
    jwt.expiration_time = ENV.fetch('JWT_EXPIRATION_TIME_MINUTES', '240').to_i.minutes.to_i
    jwt.dispatch_requests = []
    jwt.revocation_requests = []
    jwt.request_formats = { user: [:json] }
  end

  config.omniauth :google_oauth2,
                  Rails.application.credentials.dig(:oauth, :google, :client_id),
                  Rails.application.credentials.dig(:oauth, :google, :client_secret),
                  {
                    redirect_uri: ENV['OAUTH_GOOGLE_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI']
                  }

  config.omniauth :facebook,
                  Rails.application.credentials.dig(:oauth, :facebook, :app_id),
                  Rails.application.credentials.dig(:oauth, :facebook, :app_secret),
                  {
                    redirect_uri: ENV['OAUTH_FACEBOOK_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI']
                  }
end
