# frozen_string_literal: true

# Helper único de autenticação para specs de request (identity-and-auth 4.4).
#
# `sign_in_as` emite um token pelo MESMO caminho do endpoint
# (`Auth::TokenService.issue`) — não um JWT forjado à mão. É o que torna os
# testes de denylist honestos: um token de `sign_in_as` é revogável de verdade
# (seu `jti` cai no denylist no logout), então "logout invalida o token" não pode
# passar por acidente. `expired_bearer_for` é o caminho negativo — um token com
# `exp` no passado, assinado com o mesmo segredo — sem manipular JWT em cada spec.
#
# `auth_headers` é mantido para os specs herdados (user_type_gate, tenancy,
# error_response), agora sobre o token novo.
module RequestAuthHelper
  # Token real emitido para `user`. Devolve a string do token.
  def sign_in_as(user, remember_me: false)
    token, = Auth::TokenService.issue(user, remember_me: remember_me)
    token
  end

  def bearer_headers(user, remember_me: false)
    { 'Authorization' => "Bearer #{sign_in_as(user, remember_me: remember_me)}" }
  end

  # Compat com specs de channel (ActionCable), que passam o token na query.
  def access_token_for(user, expired: false)
    expired ? expired_bearer_for(user) : sign_in_as(user)
  end

  def auth_headers(user, expired: false)
    return { 'Authorization' => "Bearer #{expired_bearer_for(user)}" } if expired

    bearer_headers(user)
  end

  # Token com `exp` no passado (mesmo segredo/algoritmo do TokenService).
  def expired_bearer_for(user)
    now = Time.now.to_i
    payload = {
      'sub' => user.id.to_s,
      'jti' => SecureRandom.uuid,
      'iat' => now - 7200,
      'iat_origin' => now - 7200,
      'exp' => now - 3600
    }
    JWT.encode(payload, Auth::TokenService.secret, Auth::TokenService::ALGORITHM)
  end
end

RSpec.configure do |config|
  config.include RequestAuthHelper, type: :request
  config.include RequestAuthHelper, type: :channel
end
