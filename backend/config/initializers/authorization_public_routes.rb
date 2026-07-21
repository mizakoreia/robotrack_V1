# frozen_string_literal: true

# authorization-policies 2.5: valida a allowlist pública NO BOOT — uma entrada
# com `reason` vazio derruba a aplicação em qualquer ambiente, em vez de passar
# despercebida até a revisão seguinte.
Rails.application.config.after_initialize do
  Authorization::PublicRoutes.entries
end
