# frozen_string_literal: true

require 'rails_helper'

# identity-and-auth 4.3 / D4.7 — rack-attack no login. Uma senha mínima de 6 sem
# travamento é brute-forceável. O tráfego local (127.0.0.1) é safelisted, então o
# exercício usa um IP não-local (via REMOTE_ADDR).
RSpec.describe 'Rate limit de login', type: :request do
  let!(:ana) { create(:user, :with_password, email: 'ana@fabrica.com', password: 'senha123') }
  let(:ip) { { 'REMOTE_ADDR' => '203.0.113.7' } }

  before { Rack::Attack.cache.store.clear }
  after { Rack::Attack.cache.store.clear }

  def attempt(email:, password:, headers: ip)
    post '/auth/v1/session', params: { email: email, password: password }, headers: headers
  end

  it 'bloqueia a 11ª tentativa com 429, sem verificar a senha' do
    10.times { attempt(email: 'ana@fabrica.com', password: 'errada') }
    attempt(email: 'ana@fabrica.com', password: 'errada')

    expect(response).to have_http_status(:too_many_requests)
  end

  it 'o bloqueio é por e-mail, não global: outro e-mail do mesmo IP passa' do
    11.times { attempt(email: 'ana@fabrica.com', password: 'errada') }
    expect(response).to have_http_status(:too_many_requests)

    create(:user, :with_password, email: 'bruno@fabrica.com', password: 'senha123')
    attempt(email: 'bruno@fabrica.com', password: 'senha123')

    expect(response).to have_http_status(:ok)
  end
end
