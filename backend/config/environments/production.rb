# frozen_string_literal: true

Robotrack::Application.configure do
  # Performance
  config.cache_classes = true
  config.eager_load = true

  # Erros não detalhados em produção
  config.consider_all_requests_local = false

  # Cache (Redis)
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
    namespace: 'cache_prod',
    reconnect_attempts: 1
  }

  # Active Job
  config.active_job.queue_adapter = :sidekiq

  # Logs estruturados
  config.log_level = :info
  config.log_tags = [:request_id]
  if ENV['RAILS_LOG_TO_STDOUT'].present?
    logger = ActiveSupport::Logger.new($stdout)
    logger.formatter = Logger::Formatter.new
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Servir arquivos estáticos quando atrás de CDN ou em ambientes simples
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # SSL e segurança
  config.force_ssl = ENV.fetch('FORCE_SSL', 'true') == 'true'
  config.action_dispatch.default_headers = {
    'X-Content-Type-Options' => 'nosniff',
    'X-Frame-Options' => 'DENY',
    'Referrer-Policy' => 'strict-origin-when-cross-origin'
  }

  # Action Cable (WebSocket)
  config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'wss://example.com/cable')
  config.action_cable.allowed_request_origins = ENV
                                                .fetch('CORS_ORIGINS', 'https://example.com')
                                                .split(',')

  # I18n fallback
  config.i18n.fallbacks = true

  # Deprecations
  config.active_support.report_deprecations = false

  config.action_dispatch.cookies_same_site_protection = ENV.fetch('COOKIES_SAME_SITE', 'lax').to_sym
end
