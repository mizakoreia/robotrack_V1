# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 2.3 — liveness e readiness do orquestrador.
RSpec.describe 'Sondas de saúde', type: :request do
  describe 'GET /health/live' do
    it 'responde 200 sem autenticação e sem tocar dependências' do
      get '/health/live'
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq('status' => 'ok')
    end
  end

  describe 'GET /health/ready' do
    it 'é pública (sem Authorization) e reporta os checks' do
      get '/health/ready'
      body = JSON.parse(response.body)
      expect(body).to have_key('checks')
      expect(body['checks'].keys).to contain_exactly('database', 'redis_queue', 'migrations')
    end

    it 'com Postgres OK, o check de database é true' do
      get '/health/ready'
      expect(JSON.parse(response.body).dig('checks', 'database')).to be(true)
    end

    # REGRESSÃO do BUG 4: com TODAS as dependências no ar, o caminho feliz DEVE ser
    # 200. Antes do fix, `migrations_current?` chamava `connection.migration_context`
    # (removido no Rails 8.0 → NoMethodError engolido → sempre false), então `/ready`
    # ficava eternamente 503 e o deploy NUNCA ficava ready. Os testes acima só olhavam
    # chaves e o caminho de falha — nenhum afirmava o 200 do caminho feliz.
    it 'com todas as dependências OK (incl. migrations em dia), responde 200' do
      get '/health/ready'
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('ok')
      expect(body['checks']['migrations']).to be(true)
    end

    it 'quando um check falha (Redis fora), responde 503 (não 200)' do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError.new('redis fora'))
      get '/health/ready'
      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)['status']).to eq('degraded')
      expect(JSON.parse(response.body).dig('checks', 'redis_queue')).to be(false)
    end
  end
end
