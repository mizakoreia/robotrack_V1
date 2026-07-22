# frozen_string_literal: true

require 'rails_helper'

# hierarchy-screens 3.1–3.3 (§3.7, D-D) — a busca: escopo (projeto/célula/robô, NÃO
# tarefa), escape do curinga, `path_label` do servidor, ordem fixa e isolamento por
# tenant (RLS, não WHERE). Homônimos de outro workspace nunca entram no contador.
RSpec.describe 'Hierarchy search', :tenancy, type: :request do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def headers = auth_headers(ana).merge('X-Workspace-Id' => ws.id)

  # Dataset: um projeto "Linha 300", uma célula "Solda 01", um robô "R02 - Solda" e
  # uma TAREFA "Solda MIG" (que a busca NÃO deve achar).
  def seed_search
    in_workspace(ws) do
      p = Project.create!(name: 'Linha 300')
      c = Cell.create!(project_id: p.id, name: 'Solda 01')
      r = Robot.create!(cell_id: c.id, name: 'R02 - Solda', application: 'Solda Ponto')
      Task.create!(robot_id: r.id, workspace_id: r.workspace_id, cat: 'A. Hardware',
                   desc: 'Solda MIG', position: 0, weight: 1, progress: 0, status: 'Pendente')
      { project: p.id, cell: c.id, robot: r.id }
    end
  end

  describe 'escopo e ordem (§3.7)' do
    it 'busca "sol" acha a célula e o robô, e NÃO acha a tarefa "Solda MIG"' do
      ids = seed_search
      get '/api/v1/search', params: { q: 'sol' }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      names = body['results'].map { |r| r['name'] }
      expect(names).to include('Solda 01', 'R02 - Solda')
      expect(names).not_to include('Solda MIG') # tarefa está FORA do escopo
      expect(body['count']).to eq(2)

      # ordem fixa: célula antes de robô (projetos → células → robôs)
      types = body['results'].map { |r| r['type'] }
      expect(types).to eq(%w[cell robot])

      # path_label montado no servidor
      cell = body['results'].find { |r| r['id'] == ids[:cell] }
      expect(cell['path_label']).to eq('Célula · em Linha 300')
      expect(cell['route']).to eq("/celula/#{ids[:cell]}")
      robot = body['results'].find { |r| r['id'] == ids[:robot] }
      expect(robot['path_label']).to eq('Robô · em Solda 01 · Linha 300')
    end

    it 'busca o PROJETO por nome, com path_label "Projeto"' do
      seed_search
      get '/api/v1/search', params: { q: 'linha' }, headers: headers
      body = JSON.parse(response.body)
      hit = body['results'].find { |r| r['type'] == 'project' }
      expect(hit['name']).to eq('Linha 300')
      expect(hit['path_label']).to eq('Projeto')
      expect(hit['route']).to eq("/projeto/#{hit['id']}")
    end
  end

  describe 'escape do curinga (§3.7)' do
    it 'buscar "%" num workspace com itens retorna 0 (não o workspace inteiro)' do
      seed_search # 1 projeto + 1 célula + 1 robô, nenhum com "%" no nome
      get '/api/v1/search', params: { q: '%' }, headers: headers
      body = JSON.parse(response.body)
      expect(body['count']).to eq(0)
    end

    it 'q vazio devolve lista vazia' do
      seed_search
      get '/api/v1/search', params: { q: '' }, headers: headers
      expect(JSON.parse(response.body)).to eq('results' => [], 'count' => 0)
    end
  end

  describe 'isolamento por tenant (3.3, §4.1)' do
    let(:bob) { create(:user, name: 'Bob Outro') }
    let(:w2)  { make_workspace(owner: bob) }

    it 'homônimo de outro workspace não entra no contador (RLS, não WHERE)' do
      in_workspace(ws) { Project.create!(name: 'Solda A') }         # W1: 1 acerto
      in_workspace(w2) { Project.create!(name: 'Solda 99 SECRETO') } # W2: não deve aparecer

      get '/api/v1/search', params: { q: 'solda' }, headers: headers # headers = W1
      body = JSON.parse(response.body)
      expect(body['count']).to eq(1)
      expect(response.body).not_to include('SECRETO')
    end

    it 'pessoa que não é membro do workspace não busca (gate nega)' do
      # Ana pede busca com o X-Workspace-Id de W2, do qual ela não é membro.
      get '/api/v1/search', params: { q: 'x' },
                            headers: auth_headers(ana).merge('X-Workspace-Id' => w2.id)
      expect(response.status).to be_in([403, 404])
    end
  end
end
