# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      handle_oauth('google')
    end

    def facebook
      handle_oauth('facebook')
    end

    private

    def handle_oauth(provider)
      auth = request.env['omniauth.auth']
      info = auth.info || {}
      uid = auth.uid
      user = User.find_or_create_by_oauth(provider, uid, {
                                            email: info['email'],
                                            name: info['name'],
                                            image: info['image']
                                          })

      sign_in(user)
      token_service = Auth::TokenService.new(user)
      tokens = token_service.generate_tokens

      redirect_to (ENV['FRONTEND_CALLBACK_URL'] || ENV['OAUTH_REDIRECT_URI'] || '/auth/callback') +
                  "?provider=#{provider}&token=#{CGI.escape(tokens[:token])}&refresh_token=#{CGI.escape(tokens[:refresh_token])}"
    end
  end
end
