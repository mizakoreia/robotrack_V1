# frozen_string_literal: true

require 'rails_helper'

# internationalization G5 — a resolução de locale por requisição. X-Locale (a escolha
# do seletor) tem prioridade; Accept-Language é o fallback; fora dos suportados cai no
# default pt-BR. O locale é restaurado ao sair (I18n.with_locale).
RSpec.describe LocaleMiddleware do
  # app que devolve o I18n.locale VIGENTE dentro da requisição, como corpo.
  let(:inner) { ->(_env) { [200, {}, [I18n.locale.to_s]] } }
  subject(:mw) { described_class.new(inner) }

  def locale_seen(env) = mw.call(env).last.first

  it 'usa o X-Locale quando é suportado' do
    expect(locale_seen('HTTP_X_LOCALE' => 'en')).to eq('en')
    expect(locale_seen('HTTP_X_LOCALE' => 'pt-BR')).to eq('pt-BR')
  end

  it 'ignora X-Locale não suportado e cai no default' do
    expect(locale_seen('HTTP_X_LOCALE' => 'es')).to eq('pt-BR')
  end

  it 'usa Accept-Language quando não há X-Locale (por prefixo)' do
    expect(locale_seen('HTTP_ACCEPT_LANGUAGE' => 'en-GB,en;q=0.9')).to eq('en')
    expect(locale_seen('HTTP_ACCEPT_LANGUAGE' => 'pt-BR,pt;q=0.9')).to eq('pt-BR')
  end

  it 'X-Locale vence o Accept-Language' do
    expect(locale_seen('HTTP_X_LOCALE' => 'en', 'HTTP_ACCEPT_LANGUAGE' => 'pt-BR')).to eq('en')
  end

  it 'sem nenhum header → default pt-BR' do
    expect(locale_seen({})).to eq('pt-BR')
  end

  it 'restaura o locale ao sair (não vaza entre requisições)' do
    I18n.locale = :'pt-BR'
    mw.call('HTTP_X_LOCALE' => 'en')
    expect(I18n.locale).to eq(:'pt-BR')
  end
end
