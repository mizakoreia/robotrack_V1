# frozen_string_literal: true

require 'rails_helper'

# identity-and-auth 3.4 / D4.5 — Google OAuth por redirect. A falha a caçar é
# criar um segundo User com o mesmo e-mail (torna o casamento de Person por
# e-mail ambíguo) ou vincular com e-mail NÃO verificado (tomada de conta).
RSpec.describe 'Google OAuth callback', type: :request do
  CALLBACK = '/users/auth/google_oauth2/callback'

  before { OmniAuth.config.test_mode = true }
  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_google(uid:, email:, name: 'Operador Google', verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: uid,
      info: { email: email, name: name, image: 'https://lh3.googleusercontent.com/a/x' },
      extra: { raw_info: { email_verified: verified } }
    )
    Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]
  end

  it 'primeiro login com Google cria o usuário' do
    mock_google(uid: '10938', email: 'novo@fabrica.com', name: 'Novo Operador')

    expect { get CALLBACK }.to change(User, :count).by(1)

    user = User.find_by(email: 'novo@fabrica.com')
    expect(user.provider).to eq('google_oauth2')
    expect(user.provider_uid).to eq('10938')
    expect(user.name).to eq('Novo Operador')
    expect(response.headers['Location']).to match(/#access_token=.+&expires_at=\d+/)
  end

  it 'vincula a conta local existente em vez de duplicar' do
    ana = create(:user, :with_password, email: 'ana@fabrica.com')
    mock_google(uid: '77', email: 'ana@fabrica.com')

    expect { get CALLBACK }.not_to change(User, :count)

    ana.reload
    expect(ana.provider).to eq('google_oauth2')
    expect(ana.provider_uid).to eq('77')
    expect(User.where(email: 'ana@fabrica.com').count).to eq(1)
    expect(response.headers['Location']).to include('#access_token=')
  end

  it 'recusa e-mail não verificado e redireciona com #error' do
    create(:user, :with_password, email: 'ana@fabrica.com')
    mock_google(uid: '99', email: 'ana@fabrica.com', verified: false)

    expect { get CALLBACK }.not_to change(User, :count)

    expect(response.headers['Location']).to include('#error=email_nao_verificado')
    expect(response.headers['Location']).not_to include('access_token')
  end

  it 'uid já pertencente a outro usuário resolve para esse usuário (chave é provider/uid)' do
    x = create(:user, :google_only, email: 'x@fabrica.com')
    x.update_columns(provider: 'google_oauth2', provider_uid: '77')
    # O callback traz uid 77 (do X) mas info.email do Y.
    mock_google(uid: '77', email: 'y@fabrica.com')

    expect { get CALLBACK }.not_to change(User, :count)
    expect(response.headers['Location']).to include('#access_token=')
    # Nenhum usuário com o e-mail do Y foi criado.
    expect(User.exists?(email: 'y@fabrica.com')).to be(false)
  end

  it 'entrega o token no FRAGMENTO, nunca em query string' do
    mock_google(uid: '10938', email: 'frag@fabrica.com')

    get CALLBACK

    location = response.headers['Location']
    antes_do_hash = location.split('#').first
    expect(antes_do_hash).not_to include('access_token')
    expect(location).to match(/\#access_token=/)
  end

  it 'falha do OAuth redireciona com #error=acesso_negado' do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    Rails.application.env_config['omniauth.auth'] = nil

    get CALLBACK

    expect(response.headers['Location'].to_s).to include('#error=acesso_negado')
  end
end
