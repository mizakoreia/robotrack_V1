# frozen_string_literal: true

require_relative '../observability/log_fields'

# Log estruturado em JSON (delivery-and-observability 4.3). Uma linha por request,
# parseável, com o contexto de tenant. Ligado em produção/staging (dev mantém o
# log legível do Rails). Cobre as rotas de ActionController (health/docs/devise); o
# log das rotas Grape é instrumentado pela própria Grape em capacidade à parte —
# os campos custom (user_id/workspace_id) vêm do `Current`, comum aos dois.
Rails.application.configure do
  next unless Rails.env.production? || Rails.env.staging?

  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    Observability::LogFields.custom(
      { policy: event.payload[:policy], db_runtime: event.payload[:db_runtime] }
    )
  end
end
