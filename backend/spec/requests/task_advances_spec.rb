# frozen_string_literal: true

require 'rails_helper'

# progress-advances 4.5 (§2.4, §4.1 inv. 1/4, D3, D-409) — a suíte de request da
# trilha de avanço: a regra dura do comentário por HTTP, o 409 com corpo D-409,
# e as três negações num arquivo só — `view` sem escrita, tenant cruzado 404,
# `PATCH` de progresso 422.
RSpec.describe 'API da trilha de avanço', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  # Robô + tarefa em `progress = 45` (o ponto de partida dos casos de §2.4).
  def task_in(workspace, **attrs)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      robo = Robot.create!(cell_id: celula.id, name: 'R-01')
      create_task(robo, **{ desc: 'Power On', progress: 45, status: 'Em Andamento', position: 0 }.merge(attrs))
    end
  end

  before do
    add_member(ws, bruno, 'edit') # ganha Person (o autor do avanço)
    add_member(ws, clara, 'view')
  end

  describe 'a regra dura do comentário (§2.4 item 3)' do
    it '45 → 100 sem comentário: 201, tarefa Concluído/100' do
      tarefa = task_in(ws)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 100, lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect([body['task']['status'], body['task']['progress']]).to eq(['Concluído', 100])
      expect(body['advance']['to_progress']).to eq(100)
    end

    it '45 → 60 sem comentário: 422 e NENHUMA linha criada, tarefa intacta' do
      tarefa = task_in(ws)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 60, lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { TaskAdvance.where(task_id: tarefa.id).count }).to eq(0)
      recarregada = in_workspace(ws) { Task.find(tarefa.id) }
      expect([recarregada.status, recarregada.progress]).to eq(['Em Andamento', 45])
    end

    it '45 → 60 COM comentário: 201, Em Andamento/60' do
      tarefa = task_in(ws)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 60, comment: 'faltou aterrar', lock_version: 0 },
           headers: headers(bruno)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect([body['task']['status'], body['task']['progress']]).to eq(['Em Andamento', 60])
    end
  end

  describe 'idempotência e conflito (D-ID/D-409)' do
    it 'reenviar o MESMO uuid: 200 replay, uma única entrada' do
      tarefa = task_in(ws)
      uuid = SecureRandom.uuid
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: uuid, progress: 100, lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:created)

      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: uuid, progress: 100, lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['replay']).to be(true)
      expect(in_workspace(ws) { TaskAdvance.where(task_id: tarefa.id).count }).to eq(1)
    end

    it 'lock_version divergente: 409 com task e latest_advance no topo do corpo (D-409)' do
      tarefa = task_in(ws)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 60, comment: 'x', lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:created)

      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 80, comment: 'y', lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:conflict)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('conflito_de_versao')
      expect(body['task']['progress']).to eq(60)
      expect(body['latest_advance']['to_progress']).to eq(60)
      expect(in_workspace(ws) { TaskAdvance.where(task_id: tarefa.id).count }).to eq(1)
    end
  end

  describe 'leitura da trilha' do
    it 'view LÊ a trilha (read_workspace), mais recentes primeiro, com X-Total-Count' do
      tarefa = task_in(ws)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 60, comment: 'primeiro', lock_version: 0 }, headers: headers(bruno)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 100, lock_version: 1 }, headers: headers(bruno)

      get "/api/v1/tasks/#{tarefa.id}/advances", headers: headers(clara)
      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Total-Count']).to eq('2')
      body = JSON.parse(response.body)
      expect(body.map { |a| a['to_progress'] }).to eq([100, 60]) # mais recente primeiro
    end
  end

  describe 'as três negações num arquivo só (§4.1 inv. 1 e inv. 4)' do
    it 'view recebe 403 ao registrar avanço, sem efeito' do
      tarefa = task_in(ws)
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 100, lock_version: 0 }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { TaskAdvance.where(task_id: tarefa.id).count }).to eq(0)
      expect(in_workspace(ws) { Task.find(tarefa.id).progress }).to eq(45)
    end

    it 'PATCH com progress continua 422 read-only, apontando o endpoint de avanço' do
      tarefa = task_in(ws)
      patch "/api/v1/tasks/#{tarefa.id}",
            params: { progress: 80, lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('read_only_field')
      expect(body['details']['hint']).to include('advances')
      expect(in_workspace(ws) { Task.find(tarefa.id).progress }).to eq(45)
    end

    it 'tarefa de WS-B responde 404 byte-idêntico e não cria avanço' do
      tarefa_b = task_in(ws_b)

      post "/api/v1/tasks/#{tarefa_b.id}/advances",
           params: { id: SecureRandom.uuid, progress: 100, lock_version: 0 }, headers: headers(ana, ws)
      corpo_cross = response.body
      status_cross = response.status

      post "/api/v1/tasks/#{SecureRandom.uuid}/advances",
           params: { id: SecureRandom.uuid, progress: 100, lock_version: 0 }, headers: headers(ana, ws)

      expect(status_cross).to eq(404)
      expect(response.status).to eq(404)
      expect(corpo_cross).to eq(response.body)
      expect(in_workspace(ws_b) { TaskAdvance.where(task_id: tarefa_b.id).count }).to eq(0)
    end
  end
end
