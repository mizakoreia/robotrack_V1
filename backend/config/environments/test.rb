# frozen_string_literal: true

# authorization-policies 2.2: o gate de autorização fica LIGADO em test desde o
# dia 1 do rollout — um spec afirma isso, para a fase faseada não virar
# permanente por inércia. A tarefa 6.3 remove a flag e torna o gate
# incondicional em todos os ambientes.
ENV['AUTHZ_ENFORCE'] ||= '1'

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

  # workspace-tenancy: a conexão de runtime é robotrack_app, que NÃO é dona do
  # banco e não pode fazer DDL/purge. Por isso o schema de teste é gerenciado
  # manualmente (migrar como robotrack_migrator antes do rspec — ver
  # db/PROVISIONING.md), e o auto-maintain é desligado para não tentar um
  # `db:test:purge` que o app não tem privilégio de executar.
  config.active_record.maintain_test_schema = false
end
