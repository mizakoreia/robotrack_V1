# frozen_string_literal: true

# Helper único de autenticação para specs de request.
#
# Substitui os `bearer_for` que cada spec do template redefinia por conta
# própria. O parâmetro `expired:` existe para que o caminho NEGATIVO seja
# escrevível sem manipular JWT à mão — sem ele, testar "token expirado devolve
# 401" exigiria montar o payload e assinar manualmente em cada spec.
module RequestAuthHelper
  def auth_headers(user, expired: false)
    { 'Authorization' => "Bearer #{access_token_for(user, expired:)}" }
  end

  def access_token_for(user, expired: false)
    return Auth::TokenService.new(user).generate_tokens[:token] unless expired

    expired_token_for(user)
  end

  private

  # Assina com o mesmo segredo do TokenService, mas com `exp` no passado.
  def expired_token_for(user)
    service = Auth::TokenService.new(user)
    secret = service.instance_variable_get(:@secret)
    algorithm = service.instance_variable_get(:@algorithm) || 'HS256'

    JWT.encode(
      { sub: user.id, jti: SecureRandom.uuid, exp: 1.hour.ago.to_i, iat: 2.hours.ago.to_i },
      secret,
      algorithm
    )
  end
end

RSpec.configure do |config|
  config.include RequestAuthHelper, type: :request
  config.include RequestAuthHelper, type: :channel
end
