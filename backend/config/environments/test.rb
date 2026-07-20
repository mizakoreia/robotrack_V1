# frozen_string_literal: true

Robotrack::Application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.public_file_server.enabled = true
  config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = false
  config.action_controller.allow_forgery_protection = false
  config.action_mailer.perform_caching = false
  config.active_support.deprecation = :stderr
  config.action_cable.url = 'ws://localhost:3000/cable'
  config.action_cable.allowed_request_origins = ['http://localhost:5173', 'http://localhost:3000']
  config.action_cable.disable_request_forgery_protection = true
  config.active_job.queue_adapter = :inline
  config.active_storage.service = :test
end
