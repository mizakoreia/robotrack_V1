# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 7.4 — o teto de escrita responde 429 com Retry-After
# numérico e corpo pt-BR. IP não-local (o safelist libera 127.0.0.1).
RSpec.describe 'Rate limit por classe de domínio', type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  after { Rack::Attack.cache.store.clear }

  # Limite de escrita reduzido para o teste não precisar de 121 requisições reais.
  around do |ex|
    saved = ENV['RATE_LIMIT_WRITE']
    ENV['RATE_LIMIT_WRITE'] = '5'
    ex.run
    saved.nil? ? ENV.delete('RATE_LIMIT_WRITE') : ENV['RATE_LIMIT_WRITE'] = saved
  end

  it 'a (N+1)ª escrita no minuto responde 429 com Retry-After numérico e corpo pt-BR' do
    ip = '9.9.9.9'
    limit = RateLimits.limit(:write)

    limit.times do
      post '/api/v1/projects', params: {}, env: { 'REMOTE_ADDR' => ip }
      expect(response.status).not_to eq(429)
    end

    post '/api/v1/projects', params: {}, env: { 'REMOTE_ADDR' => ip }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After'].to_i).to be > 0
    expect(response.headers['Retry-After']).to match(/\A\d+\z/) # numérico
    body = JSON.parse(response.body)
    expect(body['error']).to include('Muitas requisições')
  end

  it 'as leituras do mesmo IP seguem passando enquanto as escritas estão no teto' do
    ip = '8.8.8.8'
    RateLimits.limit(:write).times { post '/api/v1/projects', params: {}, env: { 'REMOTE_ADDR' => ip } }
    post '/api/v1/projects', params: {}, env: { 'REMOTE_ADDR' => ip }
    expect(response).to have_http_status(:too_many_requests)

    # GET (classe read, teto 300) do mesmo IP NÃO é bloqueado pelo teto de escrita.
    get '/api/v1/projects', env: { 'REMOTE_ADDR' => ip }
    expect(response.status).not_to eq(429)
  end
end
