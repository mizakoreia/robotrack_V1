# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pré-registro', type: :request do
  let!(:client_type) do
    UserType.seed_default_types!
    UserType.client
  end

  it 'envia código para email não cadastrado e cria usuário client' do
    post '/auth/v1/pre_register', params: { identifier: 'newuser@example.com', method: 'email' }
    expect(response).to have_http_status(:created).or have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['success']).to be true
    user = User.find_by(email: 'newuser@example.com')
    expect(user).to be_present
    expect(user.user_type.name).to eq('client')
  end

  it 'valida código e conclui cadastro' do
    allow(EvolutionConnection).to receive(:send_message).and_return(true)
    post '/auth/v1/pre_register', params: { identifier: '5511999999999', method: 'whatsapp' }
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    code = LoginCode.by_destination('5511999999999').by_method('whatsapp').recent.first.code
    post '/auth/v1/verify_code', params: { identifier: '5511999999999', method: 'whatsapp', code: code }
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    post '/auth/v1/complete_registration', params: {
      identifier: '5511999999999', method: 'whatsapp', code: code, name: 'Novo Usuário', email: 'novo@example.com'
    }
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body['access_token']).to be_present
    expect(body['user']).to be_present
    expect(body['user']['email']).to eq('novo@example.com')
  end
end
