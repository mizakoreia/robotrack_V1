# frozen_string_literal: true

require_relative '../env_schema'
require_relative '../redis_topology'

# Aborta o boot em staging/production quando a topologia de Redis é insegura
# (delivery-and-observability 3.2). Roda depois do guarda de env (00_).
if Rails.env.production? || Rails.env.staging?
  urls = {
    cache: EnvSchema.redis_for(:cache),
    queue: EnvSchema.redis_for(:queue),
    cable: EnvSchema.redis_for(:cable)
  }
  channel_prefix = begin
    Rails.application.config_for(:cable)[:channel_prefix]
  rescue StandardError
    nil
  end

  problems = RedisTopology.violations(urls, channel_prefix: channel_prefix)
  unless problems.empty?
    abort("[boot abortado] topologia de Redis insegura em #{Rails.env}:\n" + problems.map { |p| "  - #{p}" }.join("\n"))
  end
end
