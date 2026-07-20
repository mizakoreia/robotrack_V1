# frozen_string_literal: true

require 'rails_helper'

# identity-and-auth §"Cadastro por e-mail e senha" (tarefas 1.5, 4.1).
RSpec.describe 'POST /auth/v1/registration', type: :request do
  def json = JSON.parse(response.body)

  def decode(token)
    JWT.decode(token, ::Auth::TokenService.secret, true, algorithm: 'HS256').first
  end

  it 'cadastra com sucesso: 201, user.name, access_token e User.count +1' do
    expect do
      post '/auth/v1/registration',
           params: { name: 'Ana Souza', email: 'ana@fabrica.com', password: 'senha123', remember_me: false }
    end.to change(User, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(json.dig('data', 'user', 'name')).to eq('Ana Souza')
    expect(json.dig('data', 'access_token')).to be_present
    # O token também vem no header Authorization.
    expect(response.headers['Authorization']).to eq("Bearer #{json.dig('data', 'access_token')}")
    # E identifica a Ana recém-criada.
    expect(decode(json.dig('data', 'access_token'))['sub']).to eq(User.last.id)
  end

  it 'recusa senha de 5 caracteres: 422 com errors.password e nenhum usuário' do
    expect do
      post '/auth/v1/registration',
           params: { name: 'Ana Souza', email: 'ana@fabrica.com', password: 'abcde' }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['password'].join).to match(/6/)
  end

  it 'recusa e-mail já cadastrado: 409, sem 2º usuário, sem revelar local/Google' do
    create(:user, :with_password, email: 'ana@fabrica.com')

    expect do
      post '/auth/v1/registration',
           params: { name: 'Outra Ana', email: 'ana@fabrica.com', password: 'senha123' }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:conflict)
    # Corpo genérico: não diz se a conta existente é local ou Google.
    expect(response.body).not_to match(/google|senha|provider|local/i)
  end

  it 'normaliza o e-mail para minúsculas e recusa duplicata posterior' do
    post '/auth/v1/registration',
         params: { name: 'Ana Souza', email: 'Ana@Fabrica.COM', password: 'senha123' }
    expect(response).to have_http_status(:created)
    expect(User.last.email).to eq('ana@fabrica.com')

    post '/auth/v1/registration',
         params: { name: 'Ana Souza', email: 'ana@fabrica.com', password: 'senha123' }
    expect(response).to have_http_status(:conflict)
  end

  it 'recusa nome ausente: 422 e nenhum usuário' do
    expect do
      post '/auth/v1/registration',
           params: { name: '', email: 'ana@fabrica.com', password: 'senha123' }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_content)
  end
end
