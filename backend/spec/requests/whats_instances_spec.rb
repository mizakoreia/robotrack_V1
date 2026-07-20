# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Whats V1 Instances', type: :request do
  let(:user_type) { UserType.create!(name: 'OG', description: 'Super Admin', hierarchy_level: 1) }
  let(:user) { User.create!(name: 'Admin', email: 'admin@example.com', user_type: user_type) }
  let!(:polemk_instance) do
    PolemkInstance.create!(
      display_name: 'Instância Teste',
      instance_name: 'TEST_INSTANCE',
      instance_id: 'inst_123',
      api_key: 'apikey_123',
      integration: 'WHATSAPP-BAILEYS',
      is_qrcode: true,
      connection_status: 'connected',
      number: '5548999999999',
      raw_response: { foo: 'bar' }
    )
  end

  def bearer_for(user)
    service = Auth::TokenService.new(user)
    tokens = service.generate_tokens
    "Bearer #{tokens[:token]}"
  end

  before do
    allow(EvolutionConnection).to receive(:instance_name).and_return('TEST')
    allow(EvolutionConnection).to receive(:connect_instance).and_return({ status: 'success',
                                                                          response: { 'qrcode' => 'BASE64DATA' } })
    allow(EvolutionConnection).to receive(:instance_connect_status).and_return({ status: 'success',
                                                                                 response: { 'state' => 'open' } })
  end

  it 'retorna QR code com usuário OG' do
    headers = { 'Authorization' => bearer_for(user) }
    get '/whats/v1/instances/connect_instance', headers: headers
    expect(response.status).to be_between(200, 201).inclusive
  end

  it 'retorna status com usuário OG' do
    headers = { 'Authorization' => bearer_for(user) }
    get '/whats/v1/instances/instance_connect_status', headers: headers
    expect(response.status).to be_between(200, 201).inclusive
  end

  it 'retorna instância atual com usuário autenticado' do
    headers = { 'Authorization' => bearer_for(user) }
    get '/whats/v1/instances/instance', headers: headers
    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    expect(body['instance_id']).to eq('inst_123')
    expect(body['instance_name']).to eq('TEST_INSTANCE')
    expect(body['display_name']).to eq('Instância Teste')
  end

  it 'retorna instância mesmo com instance_id inválido (usa a primeira)' do
    headers = { 'Authorization' => bearer_for(user) }
    get '/whats/v1/instances/instance', params: { instance_id: 'not_found' }, headers: headers
    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    expect(body['instance_id']).to eq('inst_123')
  end

  it 'retorna 401 sem token' do
    get '/whats/v1/instances/instance'
    expect(response.status).to eq(401)
  end
end
