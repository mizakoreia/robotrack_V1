# frozen_string_literal: true

require 'rails_helper'

# my-tasks-view 2.4/2.5/2.6 (§3.6, D-MTV-4/6) — a consulta única: ordenação total
# e estável, paginação sem duplicar/omitir, e o filtro por status no SERVIDOR.
RSpec.describe MyTasks::ListService, :tenancy do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  # Viewer: a Person do dono (setup — a PROVA de identidade é de §1).
  def viewer
    @viewer ||= in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) }
  end

  # Monta uma hierarquia com `n` tarefas abertas atribuídas ao viewer, distribuídas
  # em projetos/células/robôs com `position` crescente. Devolve os task_ids na
  # ORDEM hierárquica esperada.
  def seed_open_tasks(n, projects: 3, cells: 2, robots: 2)
    ids = []
    in_workspace(ws) do
      per_robot = (n.to_f / (projects * cells * robots)).ceil
      count = 0
      projects.times do |pi|
        p = Project.create!(name: "P#{pi}", position: pi)
        cells.times do |ci|
          c = Cell.create!(project_id: p.id, name: "C#{ci}", position: ci)
          robots.times do |ri|
            r = Robot.create!(cell_id: c.id, name: "R#{ri}", application: 'Solda Ponto', position: ri)
            per_robot.times do |ti|
              break if count >= n

              t = create_task(r, desc: "T#{count}", position: ti, status: 'Em Andamento', progress: 10)
              TaskAssignee.create!(task_id: t.id, person_id: viewer.id, workspace_id: ws.id)
              ids << t.id
              count += 1
            end
          end
        end
      end
    end
    ids
  end

  def page(n, per: 50)
    in_workspace(ws) do
      described_class.new.call(workspace_id: ws.id, person_id: viewer.id, page: n, per_page: per)
    end[:data]
  end

  describe 'ordenação e paginação (2.6)' do
    before { @expected = seed_open_tasks(120) }

    it 'a união das páginas 1–3 (50/pág) tem 120 task_id DISTINTOS, sem omissão nem duplicação' do
      ids = [1, 2, 3].flat_map { |p| page(p, per: 50)[:rows].map { |r| r['id'] } }
      expect(ids.size).to eq(120)
      expect(ids.uniq.size).to eq(120)
      expect(ids.to_set).to eq(@expected.to_set)
    end

    it '5 requisições da página 1 retornam a MESMA ordem (determinística)' do
      ordens = Array.new(5) { page(1, per: 50)[:rows].map { |r| r['id'] } }
      expect(ordens.uniq.size).to eq(1)
    end

    it 'a ordem segue a hierarquia projeto→célula→robô→tarefa (position)' do
      ids = [1, 2, 3].flat_map { |p| page(p, per: 50)[:rows].map { |r| r['id'] } }
      expect(ids).to eq(@expected) # a ordem de criação já é a hierárquica
    end

    it 'total reflete todas as abertas; per_page é respeitado e limitado' do
      d = page(1, per: 50)
      expect(d[:total]).to eq(120)
      expect(d[:rows].size).to eq(50)
      expect(page(1, per: 999)[:rows].size).to eq(120) # teto 200 > 120 disponíveis
    end
  end

  describe 'payload achatado (D-MTV-4)' do
    it 'cada linha traz descrição, status, progresso, e nomes+ids de robô/célula/projeto' do
      seed_open_tasks(1)
      row = page(1)[:rows].first
      expect(row.keys).to include(
        'id', 'description', 'status', 'progress', 'category',
        'robot_id', 'robot_name', 'cell_id', 'cell_name', 'project_id', 'project_name'
      )
      expect(row['status']).to eq('Em Andamento')
    end
  end
end
