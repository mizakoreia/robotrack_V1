# frozen_string_literal: true

module Auth
  class OauthService
    include ApiResponseHandler

    def initialize(provider:, provider_uid:, email:, name:, avatar_url:, ip_address:, user_agent:)
      @provider = provider
      @provider_uid = provider_uid
      @email = email
      @name = name
      @avatar_url = avatar_url
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      # Buscar ou criar usuário OAuth
      user = find_or_create_oauth_user

      # Gerar tokens JWT
      token_service = Auth::TokenService.new(user)
      tokens = token_service.generate_tokens

      # Atualizar último login
      user.update!(
        last_login_at: Time.current,
        login_count: user.login_count + 1
      )

      session_payload = {
        user: user,
        token: tokens[:token],
        refresh_token: tokens[:refresh_token],
        is_new_user: user.created_at > 5.seconds.ago
      }
      success_response(Api::Entities::AuthSession.represent(session_payload))
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def find_or_create_oauth_user
      info = { email: @email, name: @name, image: @avatar_url }
      User.find_or_create_by_oauth(@provider, @provider_uid, info)
    end
  end
end
