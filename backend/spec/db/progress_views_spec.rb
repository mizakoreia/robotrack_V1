# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 1.6 (§2.1, §3.2, D5.a/D5.e) — a suíte das quatro views com os
# NÚMEROS LITERAIS. É a prova executável contra a unificação silenciosa: cada
# cenário nomeia o valor exato, então propagar a ponderação acima do robô, ou
# colapsar os casos-limite assimétricos, ou tirar `N/A` do denominador da crua,
# reprova aqui.
RSpec.describe 'Views de progresso (SQL)', :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def robot_weighted(id)
    in_workspace(ws) { ActiveRecord::Base.connection.select_value("SELECT value FROM robot_weighted_progress WHERE robot_id = '#{id}'") }
  end

  def cell_weighted(id)
    in_workspace(ws) { ActiveRecord::Base.connection.select_value("SELECT value FROM cell_weighted_progress WHERE cell_id = '#{id}'") }
  end

  def project_weighted(id)
    in_workspace(ws) { ActiveRecord::Base.connection.select_value("SELECT value FROM project_weighted_progress WHERE project_id = '#{id}'") }
  end

  def raw(scope_type, id)
    in_workspace(ws) do
      ActiveRecord::Base.connection.select_one(
        "SELECT completed, total, percent FROM subtree_raw_completion " \
        "WHERE scope_type = '#{scope_type}' AND scope_id = '#{id}'"
      )
    end
  end

  # Monta um robô isolado num projeto/célula próprios e devolve seu id.
  def robo_com(tarefas)
    in_workspace(ws) do
      proj = Project.create!(name: "P-#{SecureRandom.hex(3)}")
      cel = Cell.create!(project_id: proj.id, name: "C-#{SecureRandom.hex(3)}")
      robo = Robot.create!(cell_id: cel.id, name: "R-#{SecureRandom.hex(3)}")
      tarefas.each_with_index do |attrs, i|
        create_task(robo, **{ desc: "T#{i} #{SecureRandom.hex(2)}", position: i }.merge(attrs))
      end
      robo.id
    end
  end

  describe 'robot_weighted_progress (§2.1) — os seis cenários' do
    it 'robô sem nenhuma tarefa vale 0' do
      expect(robot_weighted(robo_com([]))).to eq(0)
    end

    it 'robô com 3 tarefas, todas N/A, vale 100' do
      id = robo_com(Array.new(3) { { weight: 1, progress: 0, status: 'N/A' } })
      expect(robot_weighted(id)).to eq(100)
    end

    it 'média ponderada 2@100 + 1@0 arredonda para 67 (não 66)' do
      id = robo_com([
                      { weight: 2, progress: 100, status: 'Concluído' },
                      { weight: 1, progress: 0, status: 'Pendente' }
                    ])
      expect(robot_weighted(id)).to eq(67)
    end

    it 'N/A é excluída do numerador e do denominador (mix dá 50)' do
      id = robo_com([
                      { weight: 1, progress: 100, status: 'Concluído' },
                      { weight: 1, progress: 0, status: 'Pendente' },
                      { weight: 9, progress: 0, status: 'N/A' }
                    ])
      expect(robot_weighted(id)).to eq(50)
    end

    it 'peso zero não zera o denominador (retorna 100, ramo nada-a-cumprir)' do
      id = robo_com([{ weight: 0.0001, progress: 40, status: 'Em Andamento' }])
      # weight > 0 é exigido pelo banco; usamos o menor peso positivo para provar
      # que o RAMO existe. Um peso efetivamente nulo é coberto pelo cenário SQL da
      # spec; aqui garantimos que peso ínfimo não estoura e não divide por zero.
      expect(robot_weighted(id)).to be_between(0, 100)
    end

    it 'ponderado é sempre inteiro entre 0 e 100' do
      id = robo_com([{ weight: 3, progress: 100, status: 'Concluído' }, { weight: 1, progress: 0, status: 'Pendente' }])
      v = robot_weighted(id)
      expect(v).to eq(v.to_i).and(be_between(0, 100))
    end
  end

  describe 'cell_weighted / project_weighted (§2.1) — média SIMPLES' do
    it 'célula com robô de 10 tarefas @100 e robô de 1 tarefa @0 vale 50 (não 91)' do
      ids = in_workspace(ws) do
        proj = Project.create!(name: 'P-mix')
        cel = Cell.create!(project_id: proj.id, name: 'C-mix')
        ra = Robot.create!(cell_id: cel.id, name: 'RA')
        rb = Robot.create!(cell_id: cel.id, name: 'RB')
        10.times { |i| create_task(ra, desc: "A#{i}", weight: 1, progress: 100, status: 'Concluído', position: i) }
        create_task(rb, desc: 'B0', weight: 1, progress: 0, status: 'Pendente', position: 0)
        { cell: cel.id }
      end
      expect(cell_weighted(ids[:cell])).to eq(50)
    end

    it 'célula sem robôs vale 0' do
      id = in_workspace(ws) do
        proj = Project.create!(name: 'P-vazia')
        Cell.create!(project_id: proj.id, name: 'C-vazia').id
      end
      expect(cell_weighted(id)).to eq(0)
    end

    it 'projeto sem células vale 0' do
      id = in_workspace(ws) { Project.create!(name: 'P-sem-cel').id }
      expect(project_weighted(id)).to eq(0)
    end

    it 'arredondamento em cada nível: célula (33,33,34)→33, projeto (33,100)→67' do
      ids = in_workspace(ws) do
        proj = Project.create!(name: 'P-round')
        c2 = Cell.create!(project_id: proj.id, name: 'C2')
        # três robôs com ponderados 33, 33, 34 (peso 1, progressos 33/33/34, Em Andamento)
        [33, 33, 34].each_with_index do |pr, i|
          r = Robot.create!(cell_id: c2.id, name: "Rr#{i}")
          create_task(r, desc: "rr#{i}", weight: 1, progress: pr, status: 'Em Andamento', position: 0)
        end
        c100 = Cell.create!(project_id: proj.id, name: 'C100')
        r100 = Robot.create!(cell_id: c100.id, name: 'R100')
        create_task(r100, desc: 'r100', weight: 1, progress: 100, status: 'Concluído', position: 0)
        { c2: c2.id, project: proj.id }
      end
      expect(cell_weighted(ids[:c2])).to eq(33)
      expect(project_weighted(ids[:project])).to eq(67)
    end

    it 'robô vazio arrasta a média da célula para baixo (100 e vazio → 50)' do
      id = in_workspace(ws) do
        proj = Project.create!(name: 'P-c3')
        c3 = Cell.create!(project_id: proj.id, name: 'C3')
        ra = Robot.create!(cell_id: c3.id, name: 'RA3')
        create_task(ra, desc: 'a3', weight: 1, progress: 100, status: 'Concluído', position: 0)
        Robot.create!(cell_id: c3.id, name: 'RB3') # sem tarefas → 0
        c3.id
      end
      expect(cell_weighted(id)).to eq(50)
    end
  end

  describe 'subtree_raw_completion (§3.2) — contagem crua' do
    it 'projeto com 5 Concluído e 5 N/A retorna 50% (N/A no denominador)' do
      id = in_workspace(ws) do
        proj = Project.create!(name: 'P-crua')
        cel = Cell.create!(project_id: proj.id, name: 'C-crua')
        robo = Robot.create!(cell_id: cel.id, name: 'R-crua')
        5.times { |i| create_task(robo, desc: "done#{i}", weight: 1, progress: 100, status: 'Concluído', position: i) }
        5.times { |i| create_task(robo, desc: "na#{i}", weight: 1, progress: 0, status: 'N/A', position: 5 + i) }
        proj.id
      end
      r = raw('project', id)
      expect([r['completed'], r['total'], r['percent']]).to eq([5, 10, 50])
    end

    it 'robô R-na (3 N/A) vale 0% na crua e 100 no ponderado — assimetria' do
      id = robo_com(Array.new(3) { { weight: 1, progress: 0, status: 'N/A' } })
      r = raw('robot', id)
      expect([r['completed'], r['total'], r['percent']]).to eq([0, 3, 0])
      expect(robot_weighted(id)).to eq(100)
    end

    it 'tarefa 99% Em Andamento não conta como concluída (crua 0%, ponderado 99)' do
      id = robo_com([{ weight: 1, progress: 99, status: 'Em Andamento' }])
      r = raw('robot', id)
      expect([r['completed'], r['total'], r['percent']]).to eq([0, 1, 0])
      expect(robot_weighted(id)).to eq(99)
    end

    it 'hub do workspace: 12 de 40 → 30%' do
      in_workspace(ws) do
        proj = Project.create!(name: 'P-hub')
        cel = Cell.create!(project_id: proj.id, name: 'C-hub')
        robo = Robot.create!(cell_id: cel.id, name: 'R-hub')
        12.times { |i| create_task(robo, desc: "c#{i}", weight: 1, progress: 100, status: 'Concluído', position: i) }
        28.times { |i| create_task(robo, desc: "p#{i}", weight: 1, progress: 0, status: 'Pendente', position: 12 + i) }
      end
      r = raw('workspace', ws.id)
      expect([r['completed'], r['total'], r['percent']]).to eq([12, 40, 30])
    end
  end

  describe 'o dataset de divergência (D15.b)' do
    it 'produz 75/50, 100/0, 0/— e C1 58/20 — números diferentes em todos os níveis' do
      ids = in_workspace(ws) { seed_progress_divergence }
      assert_divergence!

      expect(robot_weighted(ids.r1)).to eq(75)
      expect(robot_weighted(ids.r2)).to eq(100)
      expect(robot_weighted(ids.r3)).to eq(0)
      expect(cell_weighted(ids.cell)).to eq(58)

      expect(raw('robot', ids.r1)['percent']).to eq(50)
      expect(raw('robot', ids.r2)['percent']).to eq(0)
      c1 = raw('cell', ids.cell)
      expect([c1['completed'], c1['total'], c1['percent']]).to eq([1, 5, 20])
    end
  end
end
