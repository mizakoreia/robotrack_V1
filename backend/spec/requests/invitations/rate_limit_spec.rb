# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations 6.1 / D-INV-8 — teto de tentativas nos endpoints de
# convite, e o token JAMAIS em claro no log.
#
# O tráfego local é safelisted (os outros specs fazem dezenas de chamadas como
# 127.0.0.1), então aqui se usa um IP não-local via `REMOTE_ADDR` — o mesmo
# precedente do spec de rate limit do login.
RSpec.describe 'Rate limit dos endpoints de convite', :tenancy, type: :request do
  let(:ip)     { { 'REMOTE_ADDR' => '203.0.113.42' } }
  let(:owner)  { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)     { make_workspace(owner: owner, name: 'Linha 3') }
  let(:joao)   { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }

  before do
    Rack::Attack.cache.store.clear
    Rack::Attack.enabled = true
  end

  after { Rack::Attack.cache.store.clear }

  def tentar_aceite(token, headers: {})
    post "/api/v1/invitations/#{token}/accept", headers: auth_headers(joao).merge(ip).merge(headers)
  end

  describe 'aceite: 10 por 10 minutos' do
    it 'a 11ª tentativa responde 429 com Retry-After' do
      10.times { |i| tentar_aceite("rt_inv_inexistente#{i}") }
      expect(response).to have_http_status(:not_found)

      tentar_aceite('rt_inv_inexistente_11')

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to be_present
    end

    it 'a requisição bloqueada NÃO chega ao banco' do
      10.times { |i| tentar_aceite("rt_inv_inexistente#{i}") }

      consultas = 0
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        consultas += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      end

      tentar_aceite('rt_inv_inexistente_11')

      expect(response).to have_http_status(:too_many_requests)
      expect(consultas).to eq(0)
    ensure
      ActiveSupport::Notifications.unsubscribe(assinatura)
    end
  end

  describe 'pré-visualização pública: 20 por 10 minutos' do
    it 'a 21ª tentativa responde 429' do
      20.times { |i| get "/api/v1/invitations/rt_inv_x#{i}", headers: ip }
      expect(response).to have_http_status(:not_found)

      get '/api/v1/invitations/rt_inv_x21', headers: ip

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'o teto da pré-visualização é mais folgado que o do aceite' do
      11.times { |i| get "/api/v1/invitations/rt_inv_y#{i}", headers: ip }

      # 11 chamadas bloqueariam o ACEITE; a pré-visualização ainda passa.
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'o token nunca aparece em claro no log' do
    it 'nem nos bloqueios, nem nas requisições que passaram' do
      token = "rt_inv_#{SecureRandom.urlsafe_base64(32)}"
      caminho = Rails.root.join('log', "#{Rails.env}.log")
      posicao = File.exist?(caminho) ? File.size(caminho) : 0

      20.times { tentar_aceite(token) }

      trecho = File.exist?(caminho) ? File.read(caminho).byteslice(posicao..) .to_s : ''

      expect(trecho).not_to include(token)
      expect(trecho).not_to match(/rt_inv_[A-Za-z0-9_-]{20,}/)
      # E o bloqueio foi registrado, com o hash truncado que permite
      # correlacionar tentativas do mesmo token sem reconstruí-lo.
      expect(trecho).to include('rate_limit_blocked')
      expect(trecho).to include(Digest::SHA256.hexdigest(token)[0, 12])
    end
  end

  describe 'cabeçalho anti-vazamento por referrer (6.3)' do
    it 'a pré-visualização responde com Referrer-Policy: no-referrer' do
      pessoa = in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
      convite = in_workspace(ws) { Invitation.create!(email: 'joao@fabrica.com', role: 'view', created_by_person: pessoa) }

      get "/api/v1/invitations/#{convite.token}"

      expect(response).to have_http_status(:ok)
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
    end
  end
end
