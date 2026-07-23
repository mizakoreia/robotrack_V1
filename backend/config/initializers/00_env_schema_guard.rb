# frozen_string_literal: true

require_relative '../env_schema'

# Guarda de boot (delivery-and-observability 1.1). Em `staging`/`production`, se
# QUALQUER variável obrigatória estiver ausente, aborta o boot listando TODAS de
# uma vez — em vez de subir com um default de exemplo e quebrar em produção sem um
# erro no log. Em `development`/`test` não roda: os defaults do schema valem e
# derrubar a suíte por falta de `ACTION_CABLE_URL` seria ruído.
if Rails.env.production? || Rails.env.staging?
  missing = EnvSchema.missing(Rails.env)
  unless missing.empty?
    lista = missing.map { |e| "  - #{e.name}: #{e.help}" }.join("\n")
    abort(<<~MSG)
      [boot abortado] variáveis de ambiente obrigatórias ausentes em #{Rails.env}:
      #{lista}

      Defina todas e suba de novo. (Registro: config/env_schema.rb)
    MSG
  end
end
