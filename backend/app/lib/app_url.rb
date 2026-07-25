# frozen_string_literal: true

# Origem pública do aplicativo web — workspace-invitations 2.3 / 6.3.
#
# code-only-invites removeu o link de convite (`invite_url`), único consumidor
# direto de `base`. O `base` fica porque o guarda de boot (`app_url_guard.rb`) e
# outros pontos de configuração ainda validam/consomem `APP_URL`; manter a
# validação em produção é barato e não é dívida escondida.
module AppUrl
  DEV_DEFAULT = 'http://localhost:5173'

  class MissingConfiguration < StandardError; end

  module_function

  def base
    configured = ENV['APP_URL'].to_s.strip
    return configured.chomp('/') if configured.present?

    if Rails.env.production?
      raise MissingConfiguration,
            'APP_URL é obrigatória em produção: origem pública do app web'
    end

    DEV_DEFAULT
  end
end
