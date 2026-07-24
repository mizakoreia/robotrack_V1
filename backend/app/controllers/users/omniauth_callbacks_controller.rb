# frozen_string_literal: true

require 'cgi'

module Users
  # Callback do Google OAuth (identity-and-auth 3.3 / D4.4). O token vai ao SPA
  # pelo FRAGMENTO da URL (`#access_token=…`), NUNCA em query string — o fragmento
  # não é enviado ao servidor, não entra em log de acesso nem em `Referer`. A
  # resolução de identidade (vínculo por e-mail verificado, sem duplicar) é do
  # `Auth::GoogleOauthService`.
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      user = ::Auth::GoogleOauthService.from_omniauth(request.env['omniauth.auth'])

      if user
        # workspace-core §5.1/5.2 (D-10) — bootstrap no PRIMEIRO LOGIN, também para
        # o caminho Google (que nunca passa por registration/session_service).
        # Idempotente; cura contas órfãs no próximo acesso. Sem isto, o usuário
        # Google entra sem workspace e a Visão Geral falha (BUG 6).
        ::Workspaces::BootstrapService.new(user: user).call
        token, payload = ::Auth::TokenService.issue(user, remember_me: remember_me_param)
        redirect_to_frontend("access_token=#{CGI.escape(token)}&expires_at=#{payload['exp']}")
      else
        # Recusa (e-mail não verificado): não vincula, não emite token.
        redirect_to_frontend('error=email_nao_verificado')
      end
    end

    # OmniAuth chama isto quando o usuário nega o consentimento ou a estratégia
    # falha (D4.4). Também redireciona por fragmento, sem sessão.
    def failure
      redirect_to_frontend('error=acesso_negado')
    end

    private

    def remember_me_param
      ActiveModel::Type::Boolean.new.cast(request.env.dig('omniauth.params', 'remember_me'))
    end

    def frontend_callback_url
      ENV['FRONTEND_AUTH_CALLBACK_URL'] || ENV['FRONTEND_CALLBACK_URL'] ||
        'http://localhost:5173/auth/callback'
    end

    def redirect_to_frontend(fragment)
      redirect_to "#{frontend_callback_url}##{fragment}", allow_other_host: true
    end
  end
end
