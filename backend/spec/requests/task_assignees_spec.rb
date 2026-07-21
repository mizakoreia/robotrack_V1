# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 4.5 (§3.5, §2.7, §4.1 inv. 1/4, D-RT-6, D11) — a suíte de request
# da atribuição: PUT de conjunto idempotente, diff correto, conjunto vazio,
# pessoa cross-tenant (404), `view` (403) e o evento com o diff.
RSpec.describe 'API de atribuição de responsáveis', :tenancy, type: :request do
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

  let(:tarefa) do
    robo = robot_in(ws)
    in_workspace(ws) { create_task(robo, desc: 'Atribuível') }
  end

  def person(workspace, name)
    in_workspace(workspace) { Person.create!(name: name).id }
  end

  before do
    add_member(ws, bruno, 'edit')
    add_member(ws, clara, 'view')
  end

  def assignee_ids
    in_workspace(ws) { TaskAssignee.where(task_id: tarefa.id).pluck(:person_id) }
  end

  describe 'substituição de conjunto (diff)' do
    it '[P1,P2] → [P2,P3] retorna added:[P3], removed:[P1] e não lista P2' do
      p1 = person(ws, 'P1'); p2 = person(ws, 'P2'); p3 = person(ws, 'P3')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1, p2] }, headers: headers(bruno)
      expect(response).to have_http_status(:ok)

      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p2, p3] }, headers: headers(bruno)
      body = JSON.parse(response.body)
      expect(body['added']).to eq([p3])
      expect(body['removed']).to eq([p1])
      expect(assignee_ids).to contain_exactly(p2, p3)
    end

    it 'reenviar o MESMO conjunto é idempotente: added:[] removed:[], sem duplicar' do
      p1 = person(ws, 'P1')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(bruno)
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(bruno)
      body = JSON.parse(response.body)
      expect([body['added'], body['removed']]).to eq([[], []])
      expect(assignee_ids).to eq([p1])
    end

    it 'person_ids: [] zera os responsáveis sem criar pessoa sentinela (D11)' do
      p1 = person(ws, 'P1')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(bruno)
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [] }, headers: headers(bruno)
      expect(response).to have_http_status(:ok)
      expect(assignee_ids).to eq([])
    end
  end

  describe 'isolamento e autorização' do
    it 'person_id de outro workspace responde 404, sem atribuir nada' do
      pessoa_b = person(ws_b, 'De B')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [pessoa_b] }, headers: headers(bruno)
      expect(response).to have_http_status(:not_found)
      expect(assignee_ids).to eq([])
    end

    it 'view recebe 403 no PUT, sem alterar o conjunto' do
      p1 = person(ws, 'P1')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      expect(assignee_ids).to eq([])
    end

    it 'tarefa de outro workspace responde 404' do
      robo_b = robot_in(ws_b)
      tarefa_b = in_workspace(ws_b) { create_task(robo_b, desc: 'De B') }
      pessoa_b = person(ws_b, 'Resp B')
      put "/api/v1/tasks/#{tarefa_b.id}/assignees", params: { person_ids: [pessoa_b] }, headers: headers(ana)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'evento (4.3)' do
    it 'publica task.assignees_changed com o diff; quem já era responsável não entra em added' do
      p1 = person(ws, 'P1'); p2 = person(ws, 'P2')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(bruno)

      eventos = []
      callback = ->(*args) { eventos << ActiveSupport::Notifications::Event.new(*args) }
      ActiveSupport::Notifications.subscribed(callback, 'task.assignees_changed') do
        put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1, p2] }, headers: headers(bruno)
      end

      expect(eventos.size).to eq(1)
      payload = eventos.first.payload
      expect(payload[:added]).to eq([p2])        # P1 já era responsável — não reaparece
      expect(payload[:removed]).to eq([])
      expect(payload[:task_id]).to eq(tarefa.id)
    end

    it 'não publica evento quando o conjunto não muda (re-PUT idempotente)' do
      p1 = person(ws, 'P1')
      put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(bruno)

      eventos = []
      callback = ->(*args) { eventos << args }
      ActiveSupport::Notifications.subscribed(callback, 'task.assignees_changed') do
        put "/api/v1/tasks/#{tarefa.id}/assignees", params: { person_ids: [p1] }, headers: headers(bruno)
      end
      expect(eventos).to be_empty
    end
  end
end
