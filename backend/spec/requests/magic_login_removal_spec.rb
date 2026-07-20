# frozen_string_literal: true

require 'rails_helper'

# A D4 descarta o magic-link de 6 dígitos. Esta mudança apenas REMOVE o que
# ocupa o lugar — `identity-and-auth` implementa o substituto. O que se prova
# aqui é que só o fluxo de código caiu: o OAuth continua de pé.
RSpec.describe 'Remoção do magic-login', type: :request do
  describe 'os endpoints do fluxo de código não existem mais' do
    {
      'POST /auth/v1/magic_login/request_code' => ['post', '/auth/v1/magic_login/request_code'],
      'POST /auth/v1/magic_login/validate_code' => ['post', '/auth/v1/magic_login/validate_code'],
      'POST /auth/v1/code_validation' => ['post', '/auth/v1/code_validation'],
      'POST /auth/v1/pre_register' => ['post', '/auth/v1/pre_register'],
      'POST /auth/v1/verify_code' => ['post', '/auth/v1/verify_code'],
      'POST /auth/v1/complete_registration' => ['post', '/auth/v1/complete_registration']
    }.each do |label, (verb, path)|
      it "#{label} retorna 404" do
        send(verb, path, params: { identifier: 'alguem@example.com', method: 'email' })

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  it 'GET /auth/v1/oauth/google_url continua 200 com URL do Google' do
    get '/auth/v1/oauth/google_url'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['url']).to include('accounts.google.com')
  end

  it 'User não tem mais as associações do fluxo de código' do
    names = User.reflect_on_all_associations.map(&:name)

    expect(names).not_to include(:login_codes, :login_attempts)
    expect(names).to include(:user_type)
  end

  it 'User.create! com atributos válidos persiste' do
    user = User.create!(name: 'Sem Magic', email: 'sem-magic@example.com', user_type: create(:user_type, :client))

    expect(user).to be_persisted
  end

  it 'os models do fluxo de código não são mais definidos' do
    expect(defined?(LoginCode)).to be_nil
    expect(defined?(LoginAttempt)).to be_nil
  end
end
