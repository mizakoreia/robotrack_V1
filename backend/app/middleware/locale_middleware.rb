# frozen_string_literal: true

# internationalization G5 (D-I5c/D-I6) — resolve o idioma da REQUISIÇÃO e embrulha a
# ação inteira em `I18n.with_locale`, que restaura o locale ao sair (seguro em servidor
# com threads). Assim toda renderização SÍNCRONA no servidor (o Protocolo de
# Comissionamento — `report.v1.*` resolvido na leitura; corpos de erro; rótulos de
# busca da hierarquia; e a auditoria congelada DENTRO da transação do ator) sai no
# idioma do leitor/ator, sem tocar o call-site.
#
# Fonte do locale, na ordem: header `X-Locale` (o app envia a escolha do seletor,
# `rt-lang`) → `Accept-Language` (fallback do navegador) → default (`pt-BR`). Só os
# dois locales suportados são aceitos; qualquer outro cai no default.
#
# NÃO cobre notificações (nascem em JOBS do Sidekiq, fora da requisição): essas
# congelam no locale do DESTINATÁRIO via `users.locale` (G6).
class LocaleMiddleware
  SUPPORTED = %w[pt-BR en].freeze
  DEFAULT = 'pt-BR'

  def initialize(app)
    @app = app
  end

  def call(env)
    locale = resolve(env)
    I18n.with_locale(locale) { @app.call(env) }
  end

  private

  def resolve(env)
    from_header(env['HTTP_X_LOCALE']) ||
      from_accept_language(env['HTTP_ACCEPT_LANGUAGE']) ||
      DEFAULT
  end

  # `X-Locale` exato (o app manda 'pt-BR' ou 'en').
  def from_header(value)
    return nil if value.nil?

    v = value.strip
    SUPPORTED.include?(v) ? v : nil
  end

  # Primeiro tag do Accept-Language que casa um suportado (por prefixo: `en-GB` → `en`).
  def from_accept_language(value)
    return nil if value.nil?

    value.split(',').each do |part|
      tag = part.split(';').first.to_s.strip
      next if tag.empty?

      return 'pt-BR' if tag.casecmp('pt-BR').zero? || tag.downcase.start_with?('pt')
      return 'en' if tag.downcase.start_with?('en')
    end
    nil
  end
end
