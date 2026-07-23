# frozen_string_literal: true

require 'rails_helper'

# offline-pwa 4.3 — a sonda de saúde da fila offline. Contrato: 200 sem token e
# sem X-Workspace-Id (pública e tenant-exempt), e HEAD também responde 200.
RSpec.describe 'GET/HEAD /api/v1/health', type: :request do
  it 'responde 200 sem autenticação' do
    get '/api/v1/health'
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('status' => 'ok')
  end

  it 'responde 200 sem X-Workspace-Id (tenant-exempt)' do
    get '/api/v1/health'
    expect(response).to have_http_status(:ok)
  end

  it 'HEAD responde 200 sem corpo' do
    head '/api/v1/health'
    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
  end
end
