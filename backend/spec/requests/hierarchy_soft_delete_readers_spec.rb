# frozen_string_literal: true

require 'rails_helper'

# hierarchy-soft-delete G3 (§2.9, §3.2, §3.6, §3.8, D6) — a BLINDAGEM dos leitores:
# um nó arquivado some de TODA leitura (overview, project-overview, busca, relatório
# de comissionamento, minhas-tarefas), e um pai sem filhos VIVOS ainda aparece com
# contagem 0 (não some). Arquivamento pelo serviço real do G2.
RSpec.describe 'Soft-delete: blindagem dos leitores', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)
  def owner_person = in_workspace(ws) { Person.find_or_create_by!(user_id: owner.id) { |p| p.name = 'Ana' } }
  def archive(record) = in_workspace(ws) { Hierarchy::SoftDeleteService.call(record: record) }

  describe 'Visão Geral do workspace' do
    it 'célula arquivada não conta no card; robô arquivado fora de analyzed_robots' do
      proj_id = in_workspace(ws) do
        p = Project.create!(name: 'P')
        c_live = Cell.create!(project_id: p.id, name: 'C-viva')
        c_dead = Cell.create!(project_id: p.id, name: 'C-morta')
        Robot.create!(cell_id: c_live.id, name: 'R')
        Robot.create!(cell_id: c_dead.id, name: 'R-morto')
        Hierarchy::SoftDeleteService.call(record: c_dead)
        p.id
      end
      data = in_workspace(ws) { Hierarchy::OverviewService.call(workspace_id: ws.id) }
      card = data[:projects].find { |x| x[:id] == proj_id }
      expect(card[:cells_count]).to eq(1)
      expect(data[:counts][:analyzed_robots]).to eq(1) # R-morto arquivado junto com a célula
    end

    it 'projeto só com célula arquivada AINDA aparece (cells_count 0)' do
      proj_id = in_workspace(ws) do
        p = Project.create!(name: 'PVazio')
        c = Cell.create!(project_id: p.id, name: 'ConlyDead')
        Hierarchy::SoftDeleteService.call(record: c)
        p.id
      end
      data = in_workspace(ws) { Hierarchy::OverviewService.call(workspace_id: ws.id) }
      card = data[:projects].find { |x| x[:id] == proj_id }
      expect(card).to be_present
      expect(card[:cells_count]).to eq(0)
    end
  end

  describe 'Visão do projeto' do
    it 'robô arquivado some; célula só com robô arquivado aparece com robots_count 0' do
      ids = in_workspace(ws) do
        p = Project.create!(name: 'P')
        c1 = Cell.create!(project_id: p.id, name: 'C1')
        c2 = Cell.create!(project_id: p.id, name: 'C2')
        r1 = Robot.create!(cell_id: c1.id, name: 'R1')
        Robot.create!(cell_id: c1.id, name: 'R2')
        ronly = Robot.create!(cell_id: c2.id, name: 'Ronly')
        Hierarchy::SoftDeleteService.call(record: r1)
        Hierarchy::SoftDeleteService.call(record: ronly)
        { project: p.id, c1: c1.id, c2: c2.id }
      end
      data = in_workspace(ws) { Hierarchy::ProjectOverviewService.call(project: Project.find(ids[:project])) }
      expect(data[:cells].find { |x| x[:id] == ids[:c1] }[:robots_count]).to eq(1)
      expect(data[:cells].find { |x| x[:id] == ids[:c2] }[:robots_count]).to eq(0) # célula viva, robô arquivado
      expect(data[:counts][:analyzed_robots]).to eq(1)
    end
  end

  describe 'Busca' do
    it 'nó arquivado não aparece nos resultados' do
      in_workspace(ws) do
        p = Project.create!(name: 'Zeta Linha')
        c = Cell.create!(project_id: p.id, name: 'Zeta Célula')
        r = Robot.create!(cell_id: c.id, name: 'Zeta Robô')
        Hierarchy::SoftDeleteService.call(record: r)
      end
      res = in_workspace(ws) { Hierarchy::SearchService.call(term: 'Zeta') }
      expect(res[:results].map { |x| x[:type] }).to contain_exactly('project', 'cell')
    end
  end

  describe 'Relatório de comissionamento' do
    it 'tarefa de robô arquivado e tarefa excluída individualmente somem; a viva fica' do
      owner_person
      in_workspace(ws) do
        ctx = Authorization::Context.new(user: owner, workspace: Workspace.find(ws.id))
        p = Project.create!(name: 'P', position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        r_live = Robot.create!(cell_id: c.id, name: 'Rlive', application: 'Solda Ponto', position: 0)
        r_dead = Robot.create!(cell_id: c.id, name: 'Rdead', application: 'Solda Ponto', position: 1)
        create_task(r_live, desc: 'Manter', status: 'Pendente', progress: 0, position: 0)
        t_indiv = create_task(r_live, desc: 'ExcluirUma', status: 'Pendente', progress: 0, position: 1)
        create_task(r_dead, desc: 'RoboMorto', status: 'Pendente', progress: 0, position: 0)
        Hierarchy::SoftDeleteService.call(record: r_dead)
        Tasks::DeleteService.new(context: ctx).call(id: t_indiv.id)
      end

      get '/api/v1/commissioning_report?scope=all', headers: headers
      expect(response).to have_http_status(:ok)
      tree = JSON.parse(response.body)['tree']
      robos = tree.flat_map { |pr| pr['cells'] }.flat_map { |ce| ce['robots'] }
      nomes = robos.map { |rb| rb['name'] }
      descrs = robos.flat_map { |rb| rb['tasks'] }.map { |tk| tk['description'] }

      expect(nomes).to include('Rlive')
      expect(nomes).not_to include('Rdead')
      expect(descrs).to include('Manter')
      expect(descrs).not_to include('ExcluirUma', 'RoboMorto')
    end
  end

  describe 'Minhas Tarefas' do
    it 'tarefa atribuída ao viewer some quando o robô dela é arquivado' do
      person = owner_person
      robot = nil
      in_workspace(ws) do
        p = Project.create!(name: 'P', position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        robot = Robot.create!(cell_id: c.id, name: 'R', position: 0)
        t = create_task(robot, desc: 'Minha', status: 'Pendente', progress: 0, position: 0)
        TaskAssignee.create!(task_id: t.id, person_id: person.id, workspace_id: ws.id)
      end

      get '/api/v1/my_tasks', headers: headers
      expect(JSON.parse(response.body).map { |r| r['description'] }).to include('Minha')

      archive(robot)
      get '/api/v1/my_tasks', headers: headers
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end
