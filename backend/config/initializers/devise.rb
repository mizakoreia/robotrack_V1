# frozen_string_literal: true

require 'devise/orm/active_record'
Devise.setup do |config|
  config.mailer_sender = ENV.fetch('DEVISE_MAILER_FROM', 'no-reply@robotrack.local')
  config.secret_key = Rails.application.credentials.secret_key_base

  # Senha mínima de 6, máxima de 128 (§3.1 / D4.7). A regra é reforçada pela
  # validação de model `User` (não usamos o módulo :validatable).
  config.password_length = 6..128

  config.omniauth_path_prefix = '/users/auth'
  OmniAuth.config.path_prefix = '/users/auth'

  # devise-jwt (identity-and-auth 2.1/2.2). A REVOGAÇÃO é ligada de verdade: o
  # model `JwtDenylist` inclui a estratégia `Denylist` e `User` a aponta como
  # `jwt_revocation_strategy`. A emissão e a checagem de revogação, porém, NÃO
  # passam pelo dispatch automático do Warden: ele injetaria `scp`/`aud` no
  # payload, e o contrato do token é MÍNIMO (`sub, jti, exp, iat, iat_origin` —
  # "o token identifica, não autoriza"). Por isso `Auth::TokenService` emite
  # chamando `User#jwt_payload` direto e a autenticação em api/root.rb decodifica
  # e consulta o denylist pela mesma estratégia. `dispatch_requests`/
  # `revocation_requests` ficam vazios: sem um usuário no Warden, o middleware é
  # inerte — a revogação honesta vive no TokenService + denylist.
  config.jwt do |jwt|
    jwt.secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] || Rails.application.credentials.secret_key_base
    jwt.expiration_time = ENV.fetch('JWT_TTL_SESSION_HOURS', '12').to_i.hours.to_i
    jwt.dispatch_requests = []
    jwt.revocation_requests = []
    jwt.request_formats = { user: [:json] }
  end

  # Só Google, por redirect de página inteira (identity-and-auth 3.1 / D4.4).
  # O Facebook saiu: mantê-lo configurado sem credenciais faz o boot logar warning
  # e expõe `/users/auth/facebook` como rota pública sem dono.
  config.omniauth :google_oauth2,
                  Rails.application.credentials.dig(:oauth, :google, :client_id),
                  Rails.application.credentials.dig(:oauth, :google, :client_secret),
                  {
                    redirect_uri: ENV['OAUTH_GOOGLE_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI']
                  }
end
