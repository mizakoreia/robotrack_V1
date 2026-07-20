# frozen_string_literal: true

module Auth
  # Resolução de identidade no callback do Google (identity-and-auth 3.2 / D4.5).
  #
  # E-mail é a chave: NUNCA duplica `User`. A ordem é
  #   1. por `provider`/`provider_uid` (a chave do Google);
  #   2. senão, por e-mail VERIFICADO → vincula provider/uid à conta existente;
  #   3. senão, cria.
  #
  # O vínculo (e a criação) só ocorrem com `email_verified` verdadeiro: sem isso,
  # quem criar uma conta Google com o e-mail de outra pessoa num domínio mal
  # configurado assumiria a conta RoboTrack dela. Devolve o `User` ou `nil`
  # (recusa) — o controller traduz `nil` em `#error=email_nao_verificado`.
  class GoogleOauthService
    def self.from_omniauth(auth)
      new(auth).call
    end

    def initialize(auth)
      @auth = auth
    end

    def call
      # 1. Chave do Google: provider + uid. Resolve mesmo que o e-mail do payload
      #    seja de outra pessoa (uid manda).
      by_uid = User.find_by(provider: provider, provider_uid: uid)
      return by_uid if by_uid

      return nil if email.blank? || !email_verified?

      # 2. Vincula por e-mail verificado à conta local existente (não duplica).
      existing = User.find_by(email: email)
      if existing
        existing.update!(provider: provider, provider_uid: uid,
                         avatar_url: (image.presence || existing.avatar_url))
        return existing
      end

      # 3. Cria. Nome da parte local do e-mail quando o Google não envia um (D4.6).
      User.create!(
        provider: provider, provider_uid: uid, email: email,
        name: display_name, avatar_url: image
      )
    end

    private

    attr_reader :auth

    def provider = auth.provider.to_s
    def uid      = auth.uid.to_s
    def email    = auth.dig('info', 'email').to_s.downcase.strip
    def image    = auth.dig('info', 'image').to_s

    def display_name
      raw = auth.dig('info', 'name').to_s.strip
      raw.presence || email.split('@').first
    end

    # `email_verified` pode vir em `info` ou em `extra.raw_info` (string ou bool).
    def email_verified?
      val = auth.dig('info', 'email_verified')
      val = auth.dig('extra', 'raw_info', 'email_verified') if val.nil?
      ActiveModel::Type::Boolean.new.cast(val)
    end
  end
end
