# frozen_string_literal: true

# Origem pública do aplicativo web, usada para montar o link do convite
# (`<APP_URL>/convite/<token>`) — workspace-invitations 2.3 / 6.3.
#
# Em produção a variável é OBRIGATÓRIA: um link de convite com `localhost` é um
# convite morto, e o erro só apareceria na caixa de entrada de quem foi
# convidado. Fora de produção há um padrão dev-local (a porta do Vite).
module AppUrl
  DEV_DEFAULT = 'http://localhost:5173'

  class MissingConfiguration < StandardError; end

  module_function

  def base
    configured = ENV['APP_URL'].to_s.strip
    return configured.chomp('/') if configured.present?

    if Rails.env.production?
      raise MissingConfiguration,
            'APP_URL é obrigatória em produção: sem ela os links de convite apontariam para localhost'
    end

    DEV_DEFAULT
  end

  def invite_url(token)
    "#{base}/convite/#{token}"
  end
end
