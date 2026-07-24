# frozen_string_literal: true

require 'rails_helper'

# workspace-core §5.1/5.2 (D-10) — REGRESSÃO de INTEGRAÇÃO do gancho de primeiro login
# (BUG 6, achado no smoke de deploy). Os specs de unidade chamavam `BootstrapService`
# DIRETO; NENHUM exercia registrar/logar → ver a Visão Geral. Sem o gancho ligado, o
# usuário novo entra SEM workspace e a Visão Geral falha para sempre. Esta é a rede que
# faltava: o caminho de integração, não a unidade.
RSpec.describe 'Gancho de bootstrap no primeiro login (BUG 6)', type: :request do
  def json = JSON.parse(response.body)
  def items(body) = body.is_a?(Array) ? body : (body['data'] || body['items'] || [])

  it 'registrar cria o workspace: GET /workspaces = 1 e a Visão Geral responde 200' do
    post '/auth/v1/registration',
         params: { name: 'Nova Dona', email: 'nova@fabrica.com', password: 'senha123' }
    expect(response).to have_http_status(:created)
    auth = { 'Authorization' => "Bearer #{json.dig('data', 'access_token')}" }

    get '/api/v1/workspaces', headers: auth
    expect(response).to have_http_status(:ok)
    workspaces = items(json)
    expect(workspaces.size).to eq(1)
    expect(workspaces.first['role']).to eq('owner')

    # A Visão Geral — que falhava para sempre sem workspace (o sintoma do BUG 6) —
    # agora responde 200 para o workspace recém-bootstrapado.
    get '/api/v1/projects/overview',
        headers: auth.merge('X-Workspace-Id' => workspaces.first['id'])
    expect(response).to have_http_status(:ok)
  end

  it 'login de conta ÓRFÃ (criada antes do gancho) se cura no acesso' do
    # Usuário SEM workspace, direto pela factory (não passa por registration) — simula
    # uma conta criada antes deste gancho existir.
    create(:user, :with_password, name: 'Órfã', email: 'orfa@fabrica.com')

    post '/auth/v1/session', params: { email: 'orfa@fabrica.com', password: 'senha123' }
    expect(response).to have_http_status(:ok)
    auth = { 'Authorization' => "Bearer #{json.dig('data', 'access_token')}" }

    get '/api/v1/workspaces', headers: auth
    expect(response).to have_http_status(:ok)
    expect(items(json).size).to eq(1) # o login idempotente bootstrapou a órfã
  end
end
