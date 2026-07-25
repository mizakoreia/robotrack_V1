# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
# delivery-and-observability 4.3 — `authorization` NÃO contém "token", então o
# substring-match não o pegava; `invitation_token`/`refresh_token` já eram cobertos
# por `token`, mas ficam explícitos para a intenção não depender de coincidência.
Rails.application.config.filter_parameters += %i[
  passw secret token _key crypt salt certificate otp ssn
  authorization invitation_token refresh_token
]

# invite-by-code (design D2/§B.2.8): o código de convite viaja como param `code` no
# corpo dos endpoints `/code/*`. É credencial de baixa entropia — nunca em claro no
# log. Filtro EXATO por lambda (não substring) para não redigir `country_code`,
# `zip_code` e afins, que não são segredo.
Rails.application.config.filter_parameters << lambda do |key, value|
  value.replace('[FILTERED]') if key == 'code' && value.is_a?(String)
end
