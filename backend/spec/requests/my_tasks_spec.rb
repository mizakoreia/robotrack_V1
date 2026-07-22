# frozen_string_literal: true

require 'rails_helper'

# my-tasks-view 3.1/3.4/3.5 (§3.6, §4.1, D-MTV-2/10) — o endpoint
# `GET /api/v1/my_tasks`: autenticação, autorização por membership, resolução do
# viewer pelo TOKEN (nunca por parâmetro), e o 409 de identidade ausente que
# NUNCA vira `200 []`.
RSpec.describe 'Minhas Tarefas — GET /api/v1/my_tasks', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner) }

  # Person do dono (setup); a prova de identidade real é de §1.
  let(:owner_person) { in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) } }

  def headers(user = owner) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  # A Person de `user` neste workspace (add_member devolve a Membership, não a Person).
  def person_of(user) = in_workspace(ws) { Person.find_by(user_id: user.id) }

  # Cria 1 robô e uma tarefa aberta atribuída a `person`.
  def open_task_for(person, desc: 'T1')
    @pos = (@pos || -1) + 1
    in_workspace(ws) do
      p = Project.create!(name: "P-#{desc}", position: @pos)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      t = create_task(r, desc: desc, position: 0, status: 'Em Andamento', progress: 30)
      TaskAssignee.create!(task_id: t.id, person_id: person.id, workspace_id: ws.id)
      t
    end
  end

  describe 'autenticação (§4.1 inv. 1)' do
    it '401 sem token' do
      get '/api/v1/my_tasks', headers: { 'X-Workspace-Id' => ws.id }
      expect(response).to have_http_status(:unauthorized)
    end

    it '401 mesmo com X-Skip-Auth: 1 (a brecha do template está fechada)' do
      get '/api/v1/my_tasks', headers: { 'X-Workspace-Id' => ws.id, 'X-Skip-Auth' => '1' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'autorização por membership' do
    it 'não-membro recebe 403 (coleção: o gate nega a policy; sem :id não há 404 de recurso)' do
      estranho = create(:user, name: 'Estranho')
      get '/api/v1/my_tasks', headers: auth_headers(estranho).merge('X-Workspace-Id' => ws.id)
      expect(response).to have_http_status(:forbidden)
    end

    it 'membro view LÊ as próprias tarefas (200) — a tela é leitura pura' do
      vera = create(:user, name: 'Vera View')
      add_member(ws, vera, 'view')
      open_task_for(person_of(vera), desc: 'Da Vera')

      get '/api/v1/my_tasks', headers: auth_headers(vera).merge('X-Workspace-Id' => ws.id)
      expect(response).to have_http_status(:ok)
      descs = JSON.parse(response.body).map { |r| r['description'] }
      expect(descs).to eq(['Da Vera'])
    end
  end

  describe 'viewer só do token (D-MTV-10)' do
    it '?person_id=<outra> é IGNORADO: devolve só as tarefas do viewer' do
      # dono tem 1 tarefa; um colega P2 tem outra
      open_task_for(owner_person, desc: 'Do Dono')
      bruno = create(:user, name: 'Bruno')
      add_member(ws, bruno, 'edit')
      bruno_person = person_of(bruno)
      open_task_for(bruno_person, desc: 'Do Bruno')

      get "/api/v1/my_tasks?person_id=#{bruno_person.id}", headers: headers
      expect(response).to have_http_status(:ok)
      descs = JSON.parse(response.body).map { |r| r['description'] }
      expect(descs).to eq(['Do Dono']) # NÃO as do Bruno
    end
  end

  describe 'identidade ausente = 409, nunca 200 [] (D-MTV-2)' do
    it 'membro sem Person (legado) recebe 409 person_missing' do
      # dono é membro (por owner_user_id) mas sem Person → simula linha legada
      # anterior à constraint. NÃO materializamos owner_person aqui.
      get '/api/v1/my_tasks', headers: headers
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('person_missing')
    end
  end

  describe 'paginação (D-MTV-6)' do
    it 'expõe X-Total-Count / X-Page / X-Per-Page' do
      owner_person
      open_task_for(owner_person, desc: 'Uma')
      get '/api/v1/my_tasks', headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Total-Count'].to_i).to eq(1)
      expect(response.headers['X-Page'].to_i).to eq(1)
      expect(response.headers['X-Per-Page'].to_i).to eq(50)
    end
  end
end
