# frozen_string_literal: true

module Auth
  # Purga do denylist (identity-and-auth 2.5 / D4.1). Apaga as linhas cujo `exp`
  # já passou — um token expirado já é recusado pela verificação de `exp`, então
  # mantê-lo no denylist só faz a tabela crescer e o lookup por `jti` a cada
  # request degradar. Preserva as linhas ainda vigentes (um token revogado mas
  # não expirado PRECISA continuar no denylist).
  #
  # DEPENDÊNCIA DE ENTREGA: o agendamento diário em produção (Sidekiq-cron ou
  # equivalente) é requisito de `delivery-and-observability`. Sem ele a tabela
  # cresce indefinidamente.
  class PurgeJwtDenylistJob < ApplicationJob
    queue_as :default

    def perform
      JwtDenylist.where('exp < ?', Time.current).delete_all
    end
  end
end
