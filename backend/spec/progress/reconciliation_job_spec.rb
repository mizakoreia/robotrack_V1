# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 4.6 (§D5.d, D2) — o job de reconciliação nos quatro cenários:
# divergência corrigida e alertada, execução limpa sem alerta, ausência de canal
# falhando o boot, e isolamento entre workspaces.
RSpec.describe Progress::ReconciliationJob, :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  # Robô com T1(peso2 @100 Concluído) + T2(peso1 @0 Pendente) → ponderado 67.
  def seed_robot(workspace)
    in_workspace(workspace) do
      proj = Project.create!(name: 'P')
      cel = Cell.create!(project_id: proj.id, name: 'C')
      robo = Robot.create!(cell_id: cel.id, name: 'R')
      create_task(robo, desc: 'T1', weight: 2, progress: 100, status: 'Concluído', position: 0)
      create_task(robo, desc: 'T2', weight: 1, progress: 0, status: 'Pendente', position: 1)
      Progress::BulkRecompute.call(workspace_id: workspace.id) # cache correto = 67
      robo.id
    end
  end

  def cache(workspace, robot_id)
    in_workspace(workspace) { Robot.find(robot_id).progress_cache }
  end

  def capture_events
    eventos = []
    sub = ActiveSupport::Notifications.subscribe('progress_cache.divergence') do |*, payload|
      eventos << payload
    end
    yield
    ActiveSupport::Notifications.unsubscribe(sub)
    eventos
  end

  it 'divergência plantada fora da cascata é corrigida E alertada com o valor antigo' do
    robot_id = seed_robot(ws)
    # planta 12 num robô cujo valor real é 67
    in_workspace(ws) do
      ActiveRecord::Base.connection.execute("UPDATE robots SET progress_cache = 12 WHERE id = '#{robot_id}'")
    end

    eventos = capture_events { described_class.reconcile_workspace(ws.id) }

    expect(cache(ws, robot_id)).to eq(67) # corrigido
    robo_evt = eventos.find { |e| e[:level] == 'robot' && e[:scope_id] == robot_id }
    expect(robo_evt).to include(cached: 12, computed: 67, level: 'robot', workspace_id: ws.id)
    expect(robo_evt[:row_count]).to be >= 1
  end

  it 'execução sem divergência não emite alerta nem incrementa métrica' do
    seed_robot(ws) # cache já em 67, consistente
    eventos = capture_events { described_class.reconcile_workspace(ws.id) }
    expect(eventos).to be_empty
  end

  it 'ausência do canal falha o boot em produção (não corrige em silêncio)' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    # Observability::Alert não existe no ambiente de teste
    expect { described_class.require_channel! }
      .to raise_error(/delivery-and-observability|Observability::Alert/)
  end

  it 'não cruza workspaces: divergência em W-A não escreve nem alerta W-B' do
    diego = create(:user, name: 'Diego')
    ws_b = make_workspace(owner: diego)
    robot_a = seed_robot(ws)
    robot_b = seed_robot(ws_b)

    in_workspace(ws) do
      ActiveRecord::Base.connection.execute("UPDATE robots SET progress_cache = 5 WHERE id = '#{robot_a}'")
    end

    eventos = capture_events { described_class.reconcile_workspace(ws.id) }

    expect(eventos.map { |e| e[:workspace_id] }.uniq).to eq([ws.id]) # só W-A
    expect(cache(ws, robot_a)).to eq(67)  # corrigido
    expect(cache(ws_b, robot_b)).to eq(67) # W-B intacto (nunca foi tocado)
  end
end
