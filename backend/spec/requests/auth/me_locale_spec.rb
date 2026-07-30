# frozen_string_literal: true

require 'rails_helper'

# internationalization G6 (D-I6) — a preferência de idioma da PRÓPRIA conta. O sujeito
# é o token; não há parâmetro de "quem", então ninguém altera o locale de outra pessoa.
RSpec.describe 'Preferência de idioma da conta — /auth/v1/me', type: :request do
  let(:user) { create(:user, name: 'Ana') }

  it 'GET expõe o locale da conta (default pt-BR)' do
    get '/auth/v1/me', headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('data', 'user', 'locale')).to eq('pt-BR')
  end

  it 'PATCH altera o PRÓPRIO locale' do
    patch '/auth/v1/me', params: { locale: 'en' }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('data', 'user', 'locale')).to eq('en')
    expect(user.reload.locale).to eq('en')
  end

  it 'PATCH com locale fora do par suportado → 400 e nada muda' do
    patch '/auth/v1/me', params: { locale: 'es' }, headers: auth_headers(user)
    expect(response.status).to eq(400)
    expect(user.reload.locale).to eq('pt-BR')
  end

  it 'sem token → 401 (não há caminho para alterar locale alheio)' do
    patch '/auth/v1/me', params: { locale: 'en' }
    expect(response.status).to eq(401)
    expect(user.reload.locale).to eq('pt-BR')
  end
end
