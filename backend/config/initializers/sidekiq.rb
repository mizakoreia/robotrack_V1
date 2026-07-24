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
  #
  # A constante vai como STRING de propósito: este bloco `configure_server` só
  # roda no processo SERVIDOR do Sidekiq (o worker), avaliado durante o load dos
  # inicializadores — antes do eager_load de app/lib terminar. Referenciar a
  # constante nua (`Tenant::SidekiqServerMiddleware`) aqui levanta
  # `uninitialized constant Tenant` e mata só o worker (o web pula este bloco).
  # Com a string, o Sidekiq resolve a classe na hora de USAR, já com tudo
  # carregado (BUG 9).
  config.server_middleware do |chain|
    chain.add 'Tenant::SidekiqServerMiddleware'
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: EnvSchema.redis_for(:queue),
    # Aumentando timeout para evitar erros em desenvolvimento/WSL
    timeout: 15
  }
end
