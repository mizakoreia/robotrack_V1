# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 3.7 (§3.5, §1.4, §4.1 inv. 1/4, D-RT-3, D-RT-7, D-RT-8) — a suíte
# de request do CRUD de tarefa: leitura tolerante, 409 por id e por versão, 422
# para campos read-only, 403 para `view` e 404 byte-idêntico cross-tenant.
RSpec.describe 'API de tarefas do robô', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def robot_in(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      Robot.create!(cell_id: celula.id, name: 'R-01')
    end
  end

  before do
    add_member(ws, bruno, 'edit')
    add_member(ws, clara, 'view')
  end

  describe 'leitura' do
    it 'robô sem tarefas responde 200 com tasks: [] (não 404)' do
      robo = robot_in(ws)
      get "/api/v1/robots/#{robo.id}/tasks", headers: headers(clara)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'lista ordenada por position, com assignees: []' do
      robo = robot_in(ws)
      in_workspace(ws) do
        create_task(robo, desc: 'Segunda', position: 1)
        create_task(robo, desc: 'Primeira', position: 0)
      end
      get "/api/v1/robots/#{robo.id}/tasks", headers: headers(ana)
      body = JSON.parse(response.body)
      expect(body.map { |t| t['desc'] }).to eq(['Primeira', 'Segunda'])
      expect(body.first['assignees']).to eq([])
    end

    it 'robô de outro workspace responde 404' do
      robo_b = robot_in(ws_b)
      get "/api/v1/robots/#{robo_b.id}/tasks", headers: headers(ana)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'criação' do
    it 'edit cria com uuid do cliente; segundo POST com o mesmo id é 409 sem duplicar' do
      robo = robot_in(ws)
      id = SecureRandom.uuid
      post "/api/v1/robots/#{robo.id}/tasks",
           params: { id: id, cat: 'D. Processo', desc: 'TCP Check' }, headers: headers(bruno)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['id']).to eq(id)

      post "/api/v1/robots/#{robo.id}/tasks",
           params: { id: id, cat: 'D. Processo', desc: 'Outra' }, headers: headers(bruno)
      expect(response).to have_http_status(:conflict)
      expect(in_workspace(ws) { Task.where(id: id).count }).to eq(1)
    end

    it 'position é a maior atual + 1' do
      robo = robot_in(ws)
      post "/api/v1/robots/#{robo.id}/tasks", params: { cat: 'A. Hardware', desc: 'Um' }, headers: headers(bruno)
      post "/api/v1/robots/#{robo.id}/tasks", params: { cat: 'A. Hardware', desc: 'Dois' }, headers: headers(bruno)
      posicoes = in_workspace(ws) { Task.where(robot_id: robo.id).order(:position).pluck(:position) }
      expect(posicoes).to eq([0, 1])
    end
  end

  describe 'edição' do
    it 'edita a descrição (200) e incrementa lock_version' do
      robo = robot_in(ws)
      tarefa = in_workspace(ws) { create_task(robo, desc: 'Antiga') }
      patch "/api/v1/tasks/#{tarefa.id}", params: { desc: 'Nova', lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['desc']).to eq('Nova')
      expect(in_workspace(ws) { Task.find(tarefa.id).lock_version }).to eq(1)
    end

    it 'dois PATCH com lock_version 0 produzem um 200 e um 409 (D-RT-7)' do
      robo = robot_in(ws)
      tarefa = in_workspace(ws) { create_task(robo, desc: 'X') }
      patch "/api/v1/tasks/#{tarefa.id}", params: { desc: 'A', lock_version: 0 }, headers: headers(bruno)
      primeiro = response.status
      patch "/api/v1/tasks/#{tarefa.id}", params: { desc: 'B', lock_version: 0 }, headers: headers(bruno)
      expect([primeiro, response.status]).to eq([200, 409])
      expect(JSON.parse(response.body)['error']).to eq('stale_object')
    end

    it 'PATCH com progress é 422 read-only e NÃO grava a desc (D-RT-3)' do
      robo = robot_in(ws)
      tarefa = in_workspace(ws) { create_task(robo, desc: 'Original') }
      patch "/api/v1/tasks/#{tarefa.id}",
            params: { desc: 'Invadida', progress: 50, lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('read_only_field')
      expect(in_workspace(ws) { Task.find(tarefa.id).desc }).to eq('Original')
    end

    it 'PATCH com status também é 422 read-only' do
      robo = robot_in(ws)
      tarefa = in_workspace(ws) { create_task(robo, desc: 'X') }
      patch "/api/v1/tasks/#{tarefa.id}",
            params: { status: 'Concluído', lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'exclusão' do
    it 'exclui a tarefa e suas atribuições (CASCADE), 204' do
      robo = robot_in(ws)
      tarefa_id = in_workspace(ws) do
        t = create_task(robo, desc: 'Excluível')
        TaskAssignee.create!(task: t, person: Person.create!(name: 'Resp'))
        t.id
      end
      delete "/api/v1/tasks/#{tarefa_id}", headers: headers(bruno)
      expect(response).to have_http_status(:no_content)
      expect(in_workspace(ws) { Task.exists?(tarefa_id) }).to be(false)
      expect(in_workspace(ws) { TaskAssignee.where(task_id: tarefa_id).count }).to eq(0)
    end
  end

  describe 'autorização — view não escreve' do
    it 'view recebe 403 em create/update/delete, sem efeito' do
      robo = robot_in(ws)
      tarefa = in_workspace(ws) { create_task(robo, desc: 'Intacta') }

      post "/api/v1/robots/#{robo.id}/tasks", params: { cat: 'A. Hardware', desc: 'Nova' }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/tasks/#{tarefa.id}", params: { desc: 'Mudada', lock_version: 0 }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/tasks/#{tarefa.id}", headers: headers(clara)
      expect(response).to have_http_status(:forbidden)

      expect(in_workspace(ws) { [Task.count, Task.find(tarefa.id).desc] }).to eq([1, 'Intacta'])
    end
  end

  describe 'isolamento cross-tenant (404 byte-idêntico)' do
    it 'PATCH de tarefa de WS-B responde 404 e não altera a desc' do
      robo_b = robot_in(ws_b)
      tarefa_b = in_workspace(ws_b) { create_task(robo_b, desc: 'De B') }

      patch "/api/v1/tasks/#{tarefa_b.id}", params: { desc: 'Invadida', lock_version: 0 }, headers: headers(ana)
      corpo_cross = response.body
      status_cross = response.status
      patch "/api/v1/tasks/#{SecureRandom.uuid}", params: { desc: 'X', lock_version: 0 }, headers: headers(ana)

      expect(status_cross).to eq(404)
      expect(response.status).to eq(404)
      expect(corpo_cross).to eq(response.body)
      expect(in_workspace(ws_b) { Task.find(tarefa_b.id).desc }).to eq('De B')
    end
  end
end
