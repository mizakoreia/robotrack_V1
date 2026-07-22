# frozen_string_literal: true

module Reports
  # commissioning-report 3.1 (§3.8, D-R6) — o id do documento `RT-AAAAMMDD-HHMM`.
  #
  # Gerado NO SERVIDOR, uma vez por emissão, congelado no payload e usado byte a
  # byte igual no cabeçalho, metadados e rodapé (o cliente recebe uma string, não
  # uma data para formatar — o relógio do tablet do galpão é errado e o id vai para
  # um documento assinado). NÃO é chave, não é único: duas emissões no mesmo minuto
  # dão o mesmo id — é um carimbo temporal de rastreabilidade.
  #
  # `time_zone` é PARÂMETRO (default `America/Sao_Paulo`): quando `workspace-tenancy`
  # expuser `workspace.time_zone`, passa-se o valor sem refatorar a assinatura.
  module DocumentId
    DEFAULT_TIME_ZONE = 'America/Sao_Paulo'

    module_function

    def for(instant, time_zone = DEFAULT_TIME_ZONE)
      zone = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
      instant.in_time_zone(zone).strftime('RT-%Y%m%d-%H%M')
    end
  end
end
