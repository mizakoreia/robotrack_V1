# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 5.7 (§2.5, §1.3, §4.1, D-RT-4, D-RT-5) — a suíte de lote sobre o
# catálogo padrão dos 31 templates: clamp, dedup, materialização filtrada pela
# Aplicação, catálogo vazio, rollback atômico, e a autorização/isolamento.
RSpec.describe 'API de criação de robôs em lote', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def seed_cell(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      Cell.create!(project_id: projeto.id, name: 'Célula').id
    end
  end

  def seed_catalog(workspace)
    in_workspace(workspace) { Workspaces::SeedDefaultTaskTemplatesService.new(workspace_id: workspace.id).call }
  end

  def post_batch(cell_id, application:, robots:, as: bruno, workspace: ws)
    post "/api/v1/cells/#{cell_id}/robots/batch",
         params: { application: application, robots: robots }, headers: headers(as, workspace)
  end

  def robot_task_descs(robot_id, workspace = ws)
    in_workspace(workspace) { Task.where(robot_id: robot_id).pluck(:desc) }
  end

  before do
    add_member(ws, bruno, 'edit')
    add_member(ws, clara, 'view')
    seed_catalog(ws)
  end

  describe 'clamp e dedup (§2.5)' do
    it '99 nomes válidos produzem exatamente 50 robôs' do
      cell = seed_cell(ws)
      nomes = (1..99).map { |i| { name: "R#{i}" } }
      post_batch(cell, application: 'Solda MIG', robots: nomes)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['robot_count']).to eq(50)
      expect(in_workspace(ws) { Robot.where(cell_id: cell).count }).to eq(50)
    end

    it 'dois nomes iguais produzem 1 robô; vazios são ignorados' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Solda MIG',
                       robots: [{ name: 'R01 - Solda' }, { name: 'R01 - Solda' }, { name: '   ' }])
      expect(JSON.parse(response.body)['robot_count']).to eq(1)
    end

    it 'lista normalizada vazia responde 422, sem criar robô' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Solda MIG', robots: [{ name: '' }, { name: '  ' }])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { Robot.where(cell_id: cell).count }).to eq(0)
    end
  end

  describe 'materialização filtrada pela Aplicação (§1.3)' do
    it 'robô Sealing recebe Calibração de Cola e NÃO Check sinais de Gripper' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Sealing', robots: [{ name: 'R-Sealing' }])
      robot_id = JSON.parse(response.body)['robots'].first['id']

      descs = robot_task_descs(robot_id)
      expect(descs).to include('Calibração de Cola')
      expect(descs).not_to include('Check sinais de Gripper')
      expect(descs.size).to eq(30) # 29 sem filtro + Calibração de Cola
    end

    it 'robô Solda MIG não recebe nem Calibração de Cola nem Check sinais de Gripper' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Solda MIG', robots: [{ name: 'R-MIG' }])
      robot_id = JSON.parse(response.body)['robots'].first['id']

      descs = robot_task_descs(robot_id)
      expect(descs).not_to include('Calibração de Cola')
      expect(descs).not_to include('Check sinais de Gripper')
      expect(descs.size).to eq(29)
    end

    it 'as tarefas materializadas nascem Pendente, progress 0 e position pela ordem (cat, desc)' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Solda MIG', robots: [{ name: 'R-ord' }])
      robot_id = JSON.parse(response.body)['robots'].first['id']

      in_workspace(ws) do
        tarefas = Task.where(robot_id: robot_id).order(:position)
        expect(tarefas.first.position).to eq(0)
        expect(tarefas.map(&:status).uniq).to eq(['Pendente'])
        expect(tarefas.map(&:progress).uniq).to eq([0])
        # A primeira categoria por COLLATE "C" é "A. Hardware".
        expect(tarefas.first.cat).to eq('A. Hardware')
      end
    end
  end

  describe 'catálogo vazio e atomicidade' do
    it 'catálogo vazio: 201 com robôs sem tarefas (tasks_per_robot 0)' do
      cell = seed_cell(ws)
      in_workspace(ws) { TaskTemplate.delete_all }
      post_batch(cell, application: 'Solda MIG', robots: [{ name: 'R-sem-cat' }])

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['tasks_per_robot']).to eq(0)
      robot_id = JSON.parse(response.body)['robots'].first['id']
      expect(robot_task_descs(robot_id)).to eq([])
    end

    it 'falha no meio da leva: zero robôs novos persistidos (rollback)' do
      cell = seed_cell(ws)
      in_workspace(ws) { Robot.create!(cell_id: cell, name: 'Dup', position: 0) }

      post_batch(cell, application: 'Solda MIG', robots: [{ name: 'Novo' }, { name: 'Dup' }])
      expect(response).to have_http_status(:unprocessable_entity)
      # Só o robô pré-existente permanece; "Novo" não foi persistido.
      expect(in_workspace(ws) { Robot.where(cell_id: cell).pluck(:name) }).to eq(['Dup'])
    end
  end

  describe 'autorização e isolamento' do
    it 'Aplicação fora do enum é 422, sem criar robô' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Pintura', robots: [{ name: 'R1' }])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { Robot.where(cell_id: cell).count }).to eq(0)
    end

    it 'view recebe 403, sem criar robô' do
      cell = seed_cell(ws)
      post_batch(cell, application: 'Solda MIG', robots: [{ name: 'R1' }], as: clara)
      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { Robot.where(cell_id: cell).count }).to eq(0)
    end

    it 'célula de outro workspace responde 404' do
      cell_b = seed_cell(ws_b)
      post_batch(cell_b, application: 'Solda MIG', robots: [{ name: 'R1' }], as: ana, workspace: ws)
      expect(response).to have_http_status(:not_found)
    end
  end
end
