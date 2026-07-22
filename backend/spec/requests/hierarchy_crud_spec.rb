# frozen_string_literal: true

require 'rails_helper'

# commissioning-hierarchy 4.7 (+ a metade HTTP de 3.3) — a suíte negativa do
# CRUD: cada recusa falha pelo motivo CERTO (403 papel, 404 tenant/inexistente
# byte-a-byte, 409 lock_version/nome), e a leitura é tolerante (§1.4).
RSpec.describe 'CRUD da hierarquia', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def seed_arvore
    in_workspace(ws) do
      projeto = Project.create!(name: 'Linha 1')
      celula = Cell.create!(project_id: projeto.id, name: 'Solda 01')
      robo = Robot.create!(cell_id: celula.id, name: 'R-01')
      [projeto, celula, robo]
    end
  end

  describe 'leitura tolerante (§1.4 / D-H11)' do
    it 'projeto sem células serializa cells: [], nunca null; robô sem tarefas idem' do
      projeto, celula, = seed_arvore
      in_workspace(ws) { Project.create!(name: 'Vazio') }

      get '/api/v1/projects', headers: headers(ana)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      vazio = body.find { |p| p['name'] == 'Vazio' }
      expect(vazio['cells']).to eq([])
      # progress-rollup (EXECUCAO decisão 1): `progress_cache` virou smallint (só o
      # ponderado) e a entity expõe o envelope rotulado D15, não mais o jsonb.
      expect(vazio['weighted_progress']).to eq('value' => 0, 'metric' => 'weighted', 'label' => 'Progresso ponderado')
      expect(vazio).not_to have_key('progress')

      cheio = body.find { |p| p['name'] == 'Linha 1' }
      expect(cheio['cells'].first['robots'].first['tasks']).to eq([])

      get '/api/v1/robots', params: { cell_id: celula.id }, headers: headers(ana)
      expect(JSON.parse(response.body).first['tasks_count']).to eq(0)
    end
  end

  describe 'idempotência por HTTP (3.3 / D-H2)' do
    it 'replay do mesmo POST responde 201, 200, 200 e produz UMA linha' do
      id = SecureRandom.uuid
      status_seq = 3.times.map do
        post '/api/v1/projects', params: { id: id, name: 'Offline' }, headers: headers(ana)
        response.status
      end
      expect(status_seq).to eq([201, 200, 200])
      expect(in_workspace(ws) { Project.count }).to eq(1)
    end

    it 'POST com id existente em OUTRO workspace: 404 byte-idêntico ao de id inexistente' do
      ws_b # materializa fora de qualquer contexto
      id = SecureRandom.uuid
      in_workspace(ws_b) { Project.create!(id: id, name: 'De B') }

      post '/api/v1/projects', params: { id: id, name: 'Tentativa em A' }, headers: headers(ana)
      corpo_cross = response.body
      status_cross = response.status

      post '/api/v1/cells', params: { name: 'C', project_id: SecureRandom.uuid }, headers: headers(ana)
      expect(status_cross).to eq(404)
      expect(response.status).to eq(404)
      expect(corpo_cross).to eq(response.body)
    end

    it 'UUID nulo e formato inválido respondem 422 com códigos distintos' do
      post '/api/v1/projects',
           params: { id: '00000000-0000-0000-0000-000000000000', name: 'Nulo' }, headers: headers(ana)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('invalid_id_nil_uuid')

      post '/api/v1/projects', params: { id: 'abc', name: 'Torto' }, headers: headers(ana)
      expect(JSON.parse(response.body)['error']).to eq('invalid_id_format')
    end

    it 'mesmo id com carga divergente: 409 com o recurso atual no corpo' do
      id = SecureRandom.uuid
      post '/api/v1/projects', params: { id: id, name: 'Original' }, headers: headers(ana)

      post '/api/v1/projects', params: { id: id, name: 'Divergente' }, headers: headers(ana)
      expect(response).to have_http_status(:conflict)
      corpo = JSON.parse(response.body)
      expect(corpo['error']).to eq('id_conflict')
      expect(corpo['details']['name']).to eq('Original')
    end
  end

  describe 'papel insuficiente (§4.1 — 403, nunca dado mudado)' do
    before { add_member(ws, clara, 'view') }

    it 'view não cria, não renomeia, não exclui, em nenhum nível' do
      projeto, celula, robo = seed_arvore

      post '/api/v1/cells', params: { name: 'Nova', project_id: projeto.id }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/projects/#{projeto.id}", params: { name: 'X', lock_version: 0 }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/cells/#{celula.id}", headers: headers(clara)
      expect(response).to have_http_status(:forbidden)

      expect(in_workspace(ws) { [Project.first.name, Cell.count, Robot.exists?(robo.id)] })
        .to eq(['Linha 1', 1, true])
    end

    it 'view LÊ tudo na mesma sessão (200)' do
      seed_arvore
      get '/api/v1/projects', headers: headers(clara)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
    end
  end

  describe 'outro tenant (D3.6 — 404, nunca 403)' do
    it 'usuário de W2 não lê nem escreve recurso de W1' do
      projeto, celula, = seed_arvore

      get '/api/v1/cells', params: { project_id: projeto.id }, headers: headers(diego, ws_b)
      expect(response).to have_http_status(:not_found)

      post '/api/v1/cells', params: { name: 'Invasora', project_id: projeto.id }, headers: headers(diego, ws_b)
      expect(response).to have_http_status(:not_found)

      expect(in_workspace(ws) { Cell.where(project_id: projeto.id).count }).to eq(1)
      expect(in_workspace(ws) { Cell.find(celula.id).name }).to eq('Solda 01')
    end
  end

  describe 'concorrência de edição (D-H9)' do
    it 'renomeação com lock_version antigo: 409 com o recurso atual' do
      projeto, = seed_arvore

      patch "/api/v1/projects/#{projeto.id}", params: { name: 'Primeira', lock_version: 0 }, headers: headers(ana)
      expect(response).to have_http_status(:ok)

      patch "/api/v1/projects/#{projeto.id}", params: { name: 'Atrasada', lock_version: 0 }, headers: headers(ana)
      expect(response).to have_http_status(:conflict)
      corpo = JSON.parse(response.body)
      expect(corpo['error']).to eq('stale_object')
      expect(corpo['details']['name']).to eq('Primeira')
      expect(corpo['details']['lock_version']).to eq(1)
    end

    it 'nome duplicado no escopo (renomear por cima do irmão): 409 name_taken' do
      projeto, = seed_arvore
      in_workspace(ws) { Project.create!(name: 'Linha 2') }

      alvo = in_workspace(ws) { Project.find_by(name: 'Linha 2') }
      patch "/api/v1/projects/#{alvo.id}", params: { name: 'linha 1', lock_version: 0 }, headers: headers(ana)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('name_taken')
    end
  end

  describe 'application do robô (§1.2 / D-H10)' do
    it 'sem application sai Misto / Geral; fora da lista é 422 com allowed' do
      _, celula, = seed_arvore

      post '/api/v1/robots', params: { name: 'R-02', cell_id: celula.id }, headers: headers(ana)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['application']).to eq('Misto / Geral')

      post '/api/v1/robots', params: { name: 'R-03', cell_id: celula.id, application: 'Pintura' },
           headers: headers(ana)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['details']['allowed']).to include('Solda MIG')
    end
  end
end
