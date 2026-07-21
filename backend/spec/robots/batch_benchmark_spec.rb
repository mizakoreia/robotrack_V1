# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 6.1 (§2.5, D-RT-4 riscos) — benchmark da LEVA MÁXIMA.
#
# 50 robôs × ~31 tarefas ≈ 1550 linhas numa transação. O risco é a transação
# ultrapassar o timeout de request e o usuário ver erro DEPOIS de preencher 50
# nomes. Este spec falha ANTES disso acontecer em produção: mede a leva máxima e
# exige (a) uma ÚNICA query de INSERT por tabela (insert_all, não 1550 INSERTs) e
# (b) duração bem abaixo de um timeout de request típico.
#
# O limiar aqui é CI-seguro e folgado (10 s ≪ 30 s de timeout); o alerta de
# duração de PRODUÇÃO é de `delivery-and-observability` — documentado, não
# implementado aqui.
RSpec.describe 'Benchmark da criação de robôs em lote', :tenancy do
  let(:ana) { create(:user) }
  let(:ws)  { make_workspace(owner: ana) }

  # Sealing aplica 30 dos 31 templates (29 sem filtro + Calibração de Cola);
  # 50 × 30 tarefas + 50 robôs = 1550 linhas — o caso que o proposal dimensiona.
  DURACAO_MAXIMA_S = 10
  LEVA = 50

  def contexto
    Authorization::Context.new(user: ana, workspace: Workspace.find_by(id: ws.id))
  end

  it 'cria a leva máxima com 2 INSERTs (insert_all) e bem abaixo do timeout' do
    cell_id = in_workspace(ws) do
      Workspaces::SeedDefaultTaskTemplatesService.new(workspace_id: ws.id).call
      projeto = Project.create!(name: 'Linha')
      Cell.create!(project_id: projeto.id, name: 'Célula').id
    end

    robots = Array.new(LEVA) { |i| { id: SecureRandom.uuid, name: "R#{format('%02d', i)}" } }

    inserts = Hash.new(0)
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      sql = args.last[:sql]
      inserts[:robots] += 1 if sql =~ /INSERT INTO ["`]?robots/i
      inserts[:tasks] += 1 if sql =~ /INSERT INTO ["`]?tasks/i
    end

    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = in_workspace(ws) do
      Robots::BatchCreateService.new(context: contexto).call(cell_id: cell_id, application: 'Sealing', robots: robots)
    end
    duracao = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio
    ActiveSupport::Notifications.unsubscribe(sub)

    warn "  [benchmark] leva máxima #{LEVA}×#{result[:data][:tasks_per_robot]} tarefas em #{(duracao * 1000).round} ms"

    expect(result[:status]).to eq(201)
    expect(result[:data][:robot_count]).to eq(LEVA)
    # UMA query de INSERT por tabela — não 1550.
    expect(inserts[:robots]).to eq(1)
    expect(inserts[:tasks]).to eq(1)
    expect(duracao).to be < DURACAO_MAXIMA_S

    total_tarefas = in_workspace(ws) { Task.where(robot_id: result[:data][:robots].map { |r| r[:id] }).count }
    expect(total_tarefas).to eq(LEVA * 30) # 1500 tarefas + 50 robôs = 1550 linhas
  end
end
