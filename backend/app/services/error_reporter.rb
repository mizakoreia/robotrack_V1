# frozen_string_literal: true

# Ponto único de reporte de exceção da API.
#
# Hoje só encaminha para `Rails.error`, a interface que o Rails 8 já oferece.
# É deliberado que não escolha destino: Sentry, Honeybadger ou log agregado é
# decisão de `delivery-and-observability`, que se pluga por baixo do
# `Rails.error` sem tocar no Grape. Substitui o notificador de exceção do
# template, cuja gem nunca esteve no Gemfile — toda invocação virava NameError
# dentro do próprio `rescue_from`.
module ErrorReporter
  def self.report(exception, context: {})
    Rails.error.report(exception, handled: true, context: context)
  rescue StandardError => e
    # Reportar erro nunca pode ser a causa de um novo erro.
    Rails.logger.error("ErrorReporter falhou: #{e.class}: #{e.message}")
    nil
  end
end
