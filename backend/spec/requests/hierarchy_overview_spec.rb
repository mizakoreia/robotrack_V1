# frozen_string_literal: true

require 'rails_helper'

# hierarchy-screens 2.1–2.6 (§3.2–3.4, D-A, D-C) — os três endpoints agregados de
# leitura: comportamento, contrato das duas métricas (nenhum `progress`), isolamento
# cross-tenant (404 byte-idêntico) e o orçamento de query CONSTANTE em N.
RSpec.describe 'Hierarchy overview endpoints', :tenancy, type: :request do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def headers = auth_headers(ana).merge('X-Workspace-Id' => ws.id)

  describe 'GET /api/v1/projects/overview (workspace)' do
    it 'expõe counts, raw_completion do hub e cards com cells_count + anel ponderado' do
      ids = in_workspace(ws) { seed_divergent_progress }
      get '/api/v1/projects/overview', headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body['counts']).to eq('active_projects' => 1, 'analyzed_robots' => 1)
      # hub = contagem crua do workspace: 1 de 4 → 25%
      expect(body['raw_completion']).to include('completed' => 1, 'total' => 4, 'percent' => 25, 'metric' => 'raw_count')

      card = body['projects'].find { |p| p['id'] == ids.project }
      expect(card['cells_count']).to eq(1)
      # anel = ponderado 40 — DIVERGENTE do hub (25), ambos rotulados (D15)
      expect(card['weighted_progress']).to include('value' => 40, 'metric' => 'weighted')
      expect(card['weighted_progress']['value']).not_to eq(body['raw_completion']['percent'])
    end

    it 'nenhuma chave `progress` em qualquer profundidade (contrato D-A)' do
      in_workspace(ws) { seed_divergent_progress }
      get '/api/v1/projects/overview', headers: headers
      expect(ProgressKeyScanner.offending_paths(JSON.parse(response.body))).to eq([])
    end
  end

  describe 'GET /api/v1/projects/:id/overview (projeto)' do
    it 'projeto com células: hub + cards de célula com robots_count' do
      ids = in_workspace(ws) { seed_divergent_progress }
      get "/api/v1/projects/#{ids.project}/overview", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body['counts']).to eq('configured_cells' => 1, 'analyzed_robots' => 1)
      cell = body['cells'].find { |c| c['id'] == ids.cell }
      expect(cell['robots_count']).to eq(1)
      expect(cell['weighted_progress']).to include('metric' => 'weighted')
      expect(ProgressKeyScanner.offending_paths(body)).to eq([])
    end

    it 'projeto SEM células: cells [] e hub zerado, NUNCA 404 (§3.3)' do
      pid = in_workspace(ws) { Project.create!(name: 'Vazio').id }
      get "/api/v1/projects/#{pid}/overview", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['cells']).to eq([])
      expect(body['counts']).to eq('configured_cells' => 0, 'analyzed_robots' => 0)
      expect(body['raw_completion']).to include('completed' => 0, 'total' => 0, 'percent' => 0)
    end
  end

  describe 'GET /api/v1/cells/:id/overview (célula)' do
    it 'célula: hub + cards de robô com badge = Aplicação e rodapé tasks_count' do
      ids = in_workspace(ws) { seed_divergent_progress }
      get "/api/v1/cells/#{ids.cell}/overview", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body['counts']).to eq('configured_robots' => 1)
      robot = body['robots'].find { |r| r['id'] == ids.robot }
      expect(robot['application']).to eq('Solda Ponto') # badge = Aplicação, não contagem
      expect(robot['tasks_count']).to eq(4)
      expect(robot['weighted_progress']).to include('value' => 40, 'metric' => 'weighted')
      expect(ProgressKeyScanner.offending_paths(body)).to eq([])
    end

    it 'robô com 3 tarefas todas N/A: ponderado 100, raw completed 0 (§3.4)' do
      cid, rid = in_workspace(ws) do
        p = Project.create!(name: 'P'); c = Cell.create!(project_id: p.id, name: 'C')
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Handling')
        3.times { |i| Task.create!(robot_id: r.id, workspace_id: r.workspace_id, cat: 'A. Hardware', desc: "n#{i}", position: i, weight: 1, progress: 0, status: 'N/A') }
        Progress::BulkRecompute.call(workspace_id: ws.id)
        [c.id, r.id]
      end
      get "/api/v1/cells/#{cid}/overview", headers: headers
      body = JSON.parse(response.body)
      robot = body['robots'].find { |r| r['id'] == rid }
      expect(robot['weighted_progress']['value']).to eq(100)
      expect(body['raw_completion']).to include('completed' => 0, 'total' => 3)
    end
  end

  describe 'isolamento cross-tenant (2.5, §4.1)' do
    let(:bob) { create(:user, name: 'Bob Outro') }
    let(:w2)  { make_workspace(owner: bob) }

    it 'pessoa de W1 pedindo overview de projeto de W2 recebe 404 sem vazar o nome' do
      w2_project = in_workspace(w2) { Project.create!(name: 'PROJETO SECRETO W2').id }
      get "/api/v1/projects/#{w2_project}/overview", headers: headers # headers = W1 (Ana)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('SECRETO')
    end

    it 'pessoa de W1 pedindo overview de célula de W2 recebe 404 sem vazar o nome' do
      w2_cell = in_workspace(w2) do
        p = Project.create!(name: 'P'); Cell.create!(project_id: p.id, name: 'CELULA SECRETA W2').id
      end
      get "/api/v1/cells/#{w2_cell}/overview", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('SECRETA')
    end
  end

  describe 'orçamento de query CONSTANTE em N (2.6, D-C)' do
    def build_dataset(projects:, cells:, robots:)
      in_workspace(ws) do
        projects.times do |pi|
          p = Project.create!(name: "P#{pi}", position: pi)
          cells.times do |ci|
            c = Cell.create!(project_id: p.id, name: "C#{pi}-#{ci}", position: ci)
            robots.times { |ri| Robot.create!(cell_id: c.id, name: "R#{pi}-#{ci}-#{ri}", application: 'Handling', position: ri) }
          end
        end
      end
    end

    it 'workspace overview: 20×5×8 custa ≤ 3 SELECT' do
      build_dataset(projects: 20, cells: 5, robots: 8)
      in_workspace(ws) do
        expect { Hierarchy::OverviewService.call(workspace_id: ws.id) }.to issue_at_most(3).queries
      end
    end

    it 'project overview: ≤ 3 SELECT independente do nº de células' do
      build_dataset(projects: 1, cells: 20, robots: 8)
      project = in_workspace(ws) { Project.order(:position).first }
      in_workspace(ws) do
        expect { Hierarchy::ProjectOverviewService.call(project: project) }.to issue_at_most(3).queries
      end
    end

    it 'cell overview: ≤ 3 SELECT independente do nº de robôs' do
      build_dataset(projects: 1, cells: 1, robots: 40)
      cell = in_workspace(ws) { Cell.order(:position).first }
      in_workspace(ws) do
        expect { Hierarchy::CellOverviewService.call(cell: cell) }.to issue_at_most(3).queries
      end
    end
  end
end
