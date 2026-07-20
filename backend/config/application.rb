# frozen_string_literal: true

require_relative 'boot'
if ENV['RAILS_ENV'] == 'test'
  require 'active_model/railtie'
  require 'active_job/railtie'
  require 'active_record/railtie'
  require 'action_controller/railtie'
  require 'action_mailer/railtie'
  require 'action_view/railtie'
  require 'action_cable/engine'
else
  require 'rails/all'
end

Bundler.require(*Rails.groups)

module Robotrack
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.autoload_paths = config.autoload_paths.dup

    # Configuration for the application
    config.time_zone = 'Brasilia'
    config.i18n.default_locale = :'pt-BR'
    config.i18n.available_locales = %i[pt-BR en]
    config.i18n.fallbacks = { 'pt-BR' => [:en] }

    # Enable cookies and sessions (required by OmniAuth)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: ENV.fetch('SESSION_KEY', '_robotrack_session'),
                          secure: ENV.fetch('SESSION_SECURE', 'false') == 'true',
                          same_site: ENV.fetch('COOKIES_SAME_SITE', 'lax').to_sym

    # Active Job configuration
    config.active_job.queue_adapter = :sidekiq

    # Action Cable configuration
    config.action_cable.mount_path = '/cable'
    config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'ws://localhost:3000/cable')
    config.action_cable.allowed_request_origins = ENV
                                                  .fetch('CORS_ORIGINS', 'http://localhost:5173,http://localhost:3000')
                                                  .split(',')
  end

  ActionMailer::Base.smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'localhost'),
    port: ENV.fetch('SMTP_PORT', 1025),
    domain: ENV.fetch('SMTP_DOMAIN'),
    user_name: ENV.fetch('SMTP_USERNAME'),
    password: ENV.fetch('SMTP_PASSWORD'),
    authentication: ENV.fetch('SMTP_AUTHENTICATION').to_s.downcase.to_sym,
    enable_starttls_auto: ENV.fetch('SMTP_TLS_ENABLED', 'true') == 'true',
    openssl_verify_mode: 'none'
  }
end
