# frozen_string_literal: true

require 'rails_helper'

# O RBAC por planos saiu em G4, mas o gate de autorização remanescente —
# User#og? sobre UserType — NÃO pode cair junto: ele é o único que existe até
# `workspace-tenancy` substituí-lo por Membership.role na Onda 1. Removê-lo aqui
# abriria um vão de autorização entre ondas (proposal §Não-objetivos).
RSpec.describe 'Gate de autorização por UserType', type: :request do
  let(:og) { create(:user, :og) }
  let(:client) { create(:user, :client) }

  it 'permite que um usuário og liste usuários' do
    get '/api/v1/users', headers: auth_headers(og)

    expect(response).to have_http_status(:ok)
  end

  it 'recusa um usuário client com 403' do
    get '/api/v1/users', headers: auth_headers(client)

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)['error']).to eq('forbidden')
  end

  it 'preserva os predicados que o gate usa' do
    expect(og).to be_og
    expect(client).to be_client
    expect(client).not_to be_og
  end

  # O caminho negativo do helper: sem `expired:`, provar isto exigiria montar e
  # assinar um JWT à mão dentro do spec.
  it 'recusa um og com token expirado' do
    get '/api/v1/users', headers: auth_headers(og, expired: true)

    expect(response).to have_http_status(:unauthorized)
  end
end
