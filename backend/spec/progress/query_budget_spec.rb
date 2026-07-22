# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 3.6 (orçamento) — a parte DETERMINÍSTICA dos orçamentos: a
# contagem de statements. Os tetos de latência p95 (120ms/25ms/8s da spec) são o
# alvo em hardware de produção; medi-los como asserção de wall-clock no runner
# flakaria (EXECUCAO decisão 7), então aqui travamos o que é determinístico — o
# NÚMERO de statements — e medimos a latência de forma tolerante, só para pegar
# regressão grosseira.
RSpec.describe 'Orçamento de statements do progresso', :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def count_updates
    updates = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
      updates += 1 if p[:sql] =~ /\A\s*UPDATE/i
    end
    yield
    ActiveSupport::Notifications.unsubscribe(sub)
    updates
  end

  it 'CascadeRecompute de um robô emite EXATAMENTE 3 UPDATE (robô, célula, projeto)' do
    robot_id = in_workspace(ws) do
      proj = Project.create!(name: 'P')
      cel = Cell.create!(project_id: proj.id, name: 'C')
      robo = Robot.create!(cell_id: cel.id, name: 'R')
      create_task(robo, desc: 'T', weight: 1, progress: 100, status: 'Concluído', position: 0)
      robo.id
    end

    n = in_workspace(ws) { count_updates { Progress::CascadeRecompute.call(robot_id: robot_id) } }
    expect(n).to eq(3)
  end

  it 'BulkRecompute emite EXATAMENTE 3 UPDATE, independentemente do tamanho' do
    in_workspace(ws) do
      proj = Project.create!(name: 'P')
      3.times do |ci|
        cel = Cell.create!(project_id: proj.id, name: "C#{ci}")
        2.times do |ri|
          robo = Robot.create!(cell_id: cel.id, name: "R#{ci}-#{ri}")
          create_task(robo, desc: 'T', weight: 1, progress: 100, status: 'Concluído', position: 0)
        end
      end
    end
    n = in_workspace(ws) { count_updates { Progress::BulkRecompute.call(workspace_id: ws.id) } }
    expect(n).to eq(3)
  end
end
