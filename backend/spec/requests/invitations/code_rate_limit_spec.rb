# frozen_string_literal: true

require 'rails_helper'

# invite-by-code G3.5 — tetos por CÓDIGO, mais apertados que os do token (design
# D8), em três eixos: IP, e-mail submetido e global. E o código JAMAIS em claro no
# log. Tráfego local é safelisted, então usa-se IP não-local via REMOTE_ADDR.
RSpec.describe 'Rate limit dos endpoints por código', :tenancy, type: :request do
  let(:joao) { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }

  before do
    Rack::Attack.cache.store.clear
    Rack::Attack.enabled = true
  end

  after { Rack::Attack.cache.store.clear }

  def accept(code:, email: 'joao@fabrica.com', ip: '203.0.113.42')
    post '/api/v1/invitations/code/accept',
         params: { code: code, email: email },
         headers: auth_headers(joao).merge('REMOTE_ADDR' => ip)
  end

  def preview(code:, email: 'joao@fabrica.com', ip: '203.0.113.42')
    post '/api/v1/invitations/code/preview', params: { code: code, email: email }, headers: { 'REMOTE_ADDR' => ip }
  end

  describe 'aceite por código: 5 por 10 min por IP' do
    it 'a 6ª tentativa do mesmo IP responde 429 com Retry-After' do
      5.times { |i| accept(code: "AAAA000#{i}") }
      expect(response).to have_http_status(:not_found) # código inexistente → genérico

      accept(code: 'AAAA0099')
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to be_present
    end

    it 'é mais apertado que o do token (5, não 10)' do
      5.times { |i| accept(code: "BBBB000#{i}") }
      accept(code: 'BBBB0099')
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'aceite por código: 5 por 10 min por E-MAIL submetido (outro eixo)' do
    it 'o mesmo e-mail de IPs diferentes é bloqueado na 6ª' do
      5.times { |i| accept(code: "CCCC000#{i}", email: 'alvo@fabrica.com', ip: "198.51.100.#{i + 1}") }
      accept(code: 'CCCC0099', email: 'alvo@fabrica.com', ip: '198.51.100.99')
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'pré-visualização por código: 10 por 10 min por IP' do
    it 'a 11ª tentativa responde 429' do
      10.times { |i| preview(code: "DDDD00#{format('%02d', i)}") }
      expect(response).to have_http_status(:not_found)

      preview(code: 'DDDD0099')
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'o código nunca aparece em claro no log' do
    it 'nos bloqueios, loga só o code_sha256 truncado' do
      code = '4K7P9QMX'
      caminho = Rails.root.join('log', "#{Rails.env}.log")
      posicao = File.exist?(caminho) ? File.size(caminho) : 0

      8.times { accept(code: code) } # ultrapassa o teto de 5 → gera bloqueio

      trecho = File.exist?(caminho) ? File.read(caminho).byteslice(posicao..).to_s : ''
      expect(trecho).not_to include(code)
      expect(trecho).not_to include(code.downcase)
      expect(trecho).to include('rate_limit_blocked')
      expect(trecho).to include(Digest::SHA256.hexdigest(Invitation.normalize_code(code))[0, 12])
    end
  end
end
