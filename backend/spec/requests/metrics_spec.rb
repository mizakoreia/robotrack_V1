# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 4.4 — /metrics protegido por token, formato Prometheus.
RSpec.describe 'GET /metrics', type: :request do
  around do |ex|
    saved = ENV['METRICS_TOKEN']
    ENV['METRICS_TOKEN'] = 'tok-secreto'
    ex.run
    saved.nil? ? ENV.delete('METRICS_TOKEN') : ENV['METRICS_TOKEN'] = saved
  end

  it 'sem token → 401 sem vazar valor' do
    get '/metrics'
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to match(/robotrack_/)
  end

  it 'token errado → 401' do
    get '/metrics', headers: { 'Authorization' => 'Bearer errado' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'com token → 200 em formato Prometheus com as métricas esperadas' do
    get '/metrics', headers: { 'Authorization' => 'Bearer tok-secreto' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('robotrack_sidekiq_queue_depth')
    expect(response.body).to include('robotrack_cable_connections')
    expect(response.body).to include('robotrack_workspaces_total')
    expect(response.content_type).to include('text/plain')
  end

  it 'NÃO usa workspace_id como label (cardinalidade)' do
    get '/metrics', headers: { 'Authorization' => 'Bearer tok-secreto' }
    expect(response.body).not_to match(/workspace_id=/)
  end
end
