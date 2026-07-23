# frozen_string_literal: true

require_relative '../env_schema'

Sidekiq.configure_server do |config|
  config.redis = {
    url: EnvSchema.redis_for(:queue),
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
    url: EnvSchema.redis_for(:queue),
    # Aumentando timeout para evitar erros em desenvolvimento/WSL
    timeout: 15
  }
end
