# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'

# workspace-settings 2.1/2.2/2.4 (§3.9, D10/D-PERSON-DEL) — o painel de Equipe pelo
# HTTP: listagem alfabética só das ativas + isolamento; criação (nome, user_id nulo,
# dedup por caixa, nome vazio → 422); arquivamento (apaga task_assignees, preserva
# advances, 409 p/ membro); e a matriz (view negado em escrita).
RSpec.describe 'workspace-settings — GET/POST/DELETE /api/v1/people', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def headers(user = owner) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  describe 'listagem (2.1)' do
    it 'lista só as ATIVAS, em ordem alfabética; arquivada não aparece' do
      in_workspace(ws) do
        Person.create!(name: 'Carla')
        Person.create!(name: 'Ana')
        Person.create!(name: 'Bruno')
        Person.create!(name: 'Diego', archived_at: Time.current)
      end
      get '/api/v1/people', headers: headers
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |p| p['name'] }
      expect(names).to eq(%w[Ana Bruno Carla])
    end

    it 'não vaza pessoa de outro workspace' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      in_workspace(other) { Person.create!(name: 'Eva') }
      in_workspace(ws) { Person.create!(name: 'Ana') }
      get '/api/v1/people', headers: headers
      expect(JSON.parse(response.body).map { |p| p['name'] }).to eq(['Ana'])
    end
  end

  describe 'criação (2.1)' do
    it 'edit cria pessoa sem conta (user_id nulo)' do
      vera = create(:user, name: 'Vera Edit'); add_member(ws, vera, 'edit')
      post '/api/v1/people', params: { id: SecureRandom.uuid, name: 'Fernanda' }, headers: headers(vera)
      expect(response).to have_http_status(:created).or have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Fernanda')
      expect(body['has_account']).to be(false)
    end

    it 'nome duplicado (ignorando caixa) → 422' do
      in_workspace(ws) { Person.create!(name: 'Ana') }
      post '/api/v1/people', params: { name: 'ana' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { Person.where(archived_at: nil).where("lower(btrim(name)) = 'ana'").count }).to eq(1)
    end

    it 'nome só com espaços → 422, nada criado' do
      post '/api/v1/people', params: { name: '   ' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { Person.count }).to eq(0)
    end

    it 'view é negado na criação (403), nada criado' do
      vera = create(:user, name: 'Vera View'); add_member(ws, vera, 'view')
      post '/api/v1/people', params: { name: 'X' }, headers: headers(vera)
      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { Person.where(name: 'X').count }).to eq(0)
    end
  end

  describe 'arquivamento (2.2)' do
    it 'remover apaga atribuições e preserva a trilha; a pessoa some da listagem' do
      pid = nil
      in_workspace(ws) do
        pessoa = Person.create!(name: 'Bruno')
        pid = pessoa.id
        p = Project.create!(name: 'L'); c = Cell.create!(project_id: p.id, name: 'C')
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto')
        t = create_task(r, desc: 'T', position: 0, status: 'Em Andamento', progress: 50)
        TaskAssignee.create!(task_id: t.id, person_id: pessoa.id, workspace_id: ws.id)
        TaskAdvance.create!(task_id: t.id, by: pessoa.id, author_name_snapshot: 'Bruno',
                            from_progress: 0, to_progress: 50, comment: 'x', recorded_at: Time.current)
      end
      delete "/api/v1/people/#{pid}", headers: headers
      expect(response).to have_http_status(:ok)
      # atribuições caíram; a trilha (advances) ficou; a pessoa some da lista ativa
      expect(in_workspace(ws) { TaskAssignee.where(person_id: pid).count }).to eq(0)
      expect(in_workspace(ws) { TaskAdvance.where(by: pid).count }).to eq(1)
      get '/api/v1/people', headers: headers
      expect(JSON.parse(response.body).map { |p| p['id'] }).not_to include(pid)
    end

    it 'pessoa COM membership ativa → 409, sem arquivar' do
      bruno = create(:user, name: 'Bruno Membro'); add_member(ws, bruno, 'edit')
      pid = in_workspace(ws) { Person.find_by(user_id: bruno.id).id }
      delete "/api/v1/people/#{pid}", headers: headers
      expect(response).to have_http_status(:conflict)
      expect(in_workspace(ws) { Person.find(pid).archived_at }).to be_nil
    end
  end
end
