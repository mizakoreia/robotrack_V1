# frozen_string_literal: true

Robotrack::Application.configure do
  # Reload código a cada requisição; ideal para desenvolvimento
  config.cache_classes = false
  config.eager_load = false

  # Exibe erros completos em desenvolvimento
  config.consider_all_requests_local = true

  # Cache (Redis) para paridade com produção
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
    namespace: 'cache_dev'
  }

  # Fila de jobs
  config.active_job.queue_adapter = :sidekiq

  # Action Cable (WebSocket)
  config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'ws://localhost:3000/cable')
  config.action_cable.allowed_request_origins = ENV.fetch('CORS_ORIGINS', 'http://localhost:5173,http://localhost:5174,http://localhost:3000').split(',')
  config.action_cable.disable_request_forgery_protection = true

  config.action_dispatch.cookies_same_site_protection = ENV.fetch('COOKIES_SAME_SITE', 'lax').to_sym

  config.active_storage.service = :local

  # Logs detalhados com request_id; saída em STDOUT quando configurado
  config.log_level = :debug
  config.log_tags = [:request_id]
  if ENV['RAILS_LOG_TO_STDOUT'].present?
    logger = ActiveSupport::Logger.new($stdout)
    logger.formatter = Logger::Formatter.new
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Servir arquivos estáticos em dev quando necessário (Swagger JSON, etc.)
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Facilita desenvolvimento local/WSL com diferentes hosts
  config.hosts.clear

  # quality-and-accessibility 2.1 — chave de tradução inexistente LEVANTA em dev
  # (pega cedo, antes de virar "translation missing:" numa linha imutável).
  config.i18n.raise_on_missing_translations = true
end
