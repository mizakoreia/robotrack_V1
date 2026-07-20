# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'

# workspace-core §"Índice do usuário" e §"Imutabilidade" (tarefas 6.1, 6.2, 6.4).
RSpec.describe 'Superfície HTTP de workspaces', :tenancy, type: :request do
  let(:user) { create(:user) }

  def json
    JSON.parse(response.body)
  end

  # ---- 6.1 índice ------------------------------------------------------------
  describe 'GET /api/v1/workspaces' do
    it 'reflete propriedade e membership, sem workspaces alheios' do
      ws_a = make_workspace(owner: user)
      ws_b = make_workspace
      ws_c = make_workspace
      add_member(ws_b, user, 'view')

      get '/api/v1/workspaces', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      by_id = json.to_h { |i| [i['id'], i['role']] }
      expect(by_id[ws_a.id]).to eq('owner')
      expect(by_id[ws_b.id]).to eq('view')
      expect(by_id).not_to have_key(ws_c.id)
      expect(json.size).to eq(2)
    end
  end

  # ---- 6.2 imutabilidade do dono via API ------------------------------------
  describe 'PATCH /api/v1/workspaces/:id' do
    it 'permite ao dono renomear (200)' do
      ws = make_workspace(owner: user)
      patch "/api/v1/workspaces/#{ws.id}", params: { name: 'Comissionamento Planta 2' },
                                           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json['name']).to eq('Comissionamento Planta 2')
    end

    it 'rejeita troca de dono com 422 e mantém o owner_user_id' do
      ws = make_workspace(owner: user)
      outro = create(:user)

      patch "/api/v1/workspaces/#{ws.id}", params: { name: 'x', owner_user_id: outro.id },
                                           headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      persisted = in_workspace(ws) { Workspace.find(ws.id).owner_user_id }
      expect(persisted).to eq(user.id)
    end

    it 'nega a não-dono' do
      ws = make_workspace
      add_member(ws, user, 'edit')
      patch "/api/v1/workspaces/#{ws.id}", params: { name: 'tentativa' }, headers: auth_headers(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---- 6.4 superfície negativa (adulteração de índice/papel/bypass) ---------
  describe 'não confia no cliente' do
    def probe(user, headers)
      get '/api/v1/tenancy_probe/context', headers: auth_headers(user).merge(headers)
    end

    it 'X-Workspace-Id de workspace alheio devolve 403, mesmo com papel forjado' do
      alheio = make_workspace # não é do user
      probe(user, 'X-Workspace-Id' => alheio.id, 'X-Role' => 'owner')
      expect(response).to have_http_status(:forbidden)
    end

    it 'X-Skip-Auth em rota de domínio devolve 401' do
      get '/api/v1/tenancy_probe/context', headers: { 'X-Skip-Auth' => '1', 'X-Workspace-Id' => SecureRandom.uuid }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'papel enviado pelo cliente é ignorado: membro view continua view' do
      ws = make_workspace
      add_member(ws, user, 'view')
      probe(user, 'X-Workspace-Id' => ws.id, 'X-Role' => 'owner', 'role' => 'owner')

      expect(response).to have_http_status(:ok)
      expect(json['role']).to eq('view')
    end
  end
end
