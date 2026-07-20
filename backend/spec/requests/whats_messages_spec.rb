# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Whats V1 Messages', type: :request do
  let(:user_type) { UserType.create!(name: 'OG', description: 'Super Admin', hierarchy_level: 1) }
  let(:user) { User.create!(name: 'Admin', email: 'admin@example.com', user_type: user_type) }

  def bearer_for(user)
    service = Auth::TokenService.new(user)
    tokens = service.generate_tokens
    "Bearer #{tokens[:token]}"
  end

  before do
    allow(EvolutionConnection).to receive(:instance_name).and_return('TEST')
    allow(EvolutionConnection).to receive(:send_message).and_return({ status: 'success',
                                                                      response: { 'id' => 'MSG123',
                                                                                  'status' => 'queued' } })
  end

  it 'envia mensagem com usuário OG autenticado' do
    headers = { 'Authorization' => bearer_for(user) }
    post '/whats/v1/messages/send_message', params: { number: '5511999999999', text: 'Olá' }, headers: headers
    expect(response.status).to eq(201)
    body = JSON.parse(response.body)
    expect(body['data']).to include('id' => 'MSG123')
  end

  it 'retorna 401 sem autorização' do
    post '/whats/v1/messages/send_message', params: { number: '5511999999999', text: 'Olá' }
    expect(response.status).to eq(401)
  end
end
