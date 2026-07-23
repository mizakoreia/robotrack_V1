# frozen_string_literal: true

require_relative '../observability/scrubber'

# Rastreio de exceção (delivery-and-observability 4.1). Sem DSN o Sentry é no-op —
# dev/test não enviam nada. `send_default_pii: false` + o `before_send` com o
# Scrubber garantem que corpo/headers com segredo não viajem. O contexto de tenant
# (user_id, workspace_id, request_id, rota) é anexado no before-hook do Grape.
if defined?(Sentry) && ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.breadcrumbs_logger = [:active_support_logger]
    config.environment = Rails.env
    config.release = ENV['SENTRY_RELEASE'] || ENV['GIT_SHA']
    config.send_default_pii = false
    config.traces_sample_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', '0.0').to_f

    # O corpo da requisição é redigido pelo `filter_parameters` do Rails (Sentry-
    # rails o respeita com `send_default_pii: false`). O `before_send` cobre o
    # `extra` custom, onde um contexto de debug poderia carregar um token.
    config.before_send = lambda do |event, _hint|
      event.extra = Observability::Scrubber.scrub(event.extra) if event.respond_to?(:extra) && event.extra
      event
    end
  end
end
