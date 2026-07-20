# frozen_string_literal: true

require 'rails_helper'

# O RBAC por planos saiu em G4, mas o gate de autorização remanescente —
# User#og? sobre UserType — NÃO pode cair junto: ele é o único que existe até
# `workspace-tenancy` substituí-lo por Membership.role na Onda 1. Removê-lo aqui
# abriria um vão de autorização entre ondas (proposal §Não-objetivos).
RSpec.describe 'Gate de autorização por UserType', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { User.create!(name: 'OG', email: 'og-gate@example.com', user_type: UserType.og) }
  let(:client) { User.create!(name: 'Cliente', email: 'client-gate@example.com', user_type: UserType.client) }

  def auth_for(user)
    { 'Authorization' => "Bearer #{Auth::TokenService.new(user).generate_tokens[:token]}" }
  end

  it 'permite que um usuário og liste usuários' do
    get '/api/v1/users', headers: auth_for(og)

    expect(response).to have_http_status(:ok)
  end

  it 'recusa um usuário client com 403' do
    get '/api/v1/users', headers: auth_for(client)

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)['error']).to eq('forbidden')
  end

  it 'preserva os predicados que o gate usa' do
    expect(og).to be_og
    expect(client).to be_client
    expect(client).not_to be_og
  end
end
