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
