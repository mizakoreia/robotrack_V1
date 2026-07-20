# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
    # Aumentando timeout para evitar erros em desenvolvimento/WSL
    timeout: 15
  }

  # workspace-tenancy 4.3: abre o contexto de tenant de todo job de domínio a
  # partir do workspace_id (primeiro argumento).
  config.server_middleware do |chain|
    chain.add Tenant::SidekiqServerMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
    # Aumentando timeout para evitar erros em desenvolvimento/WSL
    timeout: 15
  }
end
