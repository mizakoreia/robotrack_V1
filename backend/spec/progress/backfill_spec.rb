# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 5.1/5.3 (§4.4, §1.4) — o backfill de dado importado: o dump
# pré-destrutivo é verificável por contagem de linhas, e a reconciliação rodada
# LOGO APÓS uma "importação" (bulk seed) exige ZERO divergência — qualquer
# divergência aqui é bug de importador ou de view, não cache velho.
RSpec.describe 'Backfill de progresso pós-importação', :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  # "Importa" um workspace do jeito que o importador legado fará (5.2): rows em
  # massa sob without_cascade, BulkRecompute uma vez no fim.
  def import_workspace
    in_workspace(ws) do
      Progress.without_cascade do
        proj = Project.create!(name: 'Importado')
        2.times do |ci|
          cel = Cell.create!(project_id: proj.id, name: "C#{ci}")
          2.times do |ri|
            robo = Robot.create!(cell_id: cel.id, name: "R#{ci}-#{ri}")
            create_task(robo, desc: 'T1', weight: 2, progress: 100, status: 'Concluído', position: 0)
            create_task(robo, desc: 'T2', weight: 1, progress: 0, status: 'Pendente', position: 1)
          end
        end
      end
      Progress::BulkRecompute.call(workspace_id: ws.id)
    end
  end

  it '5.1 — o dump escreve uma linha por escopo e a contagem por nível bate' do
    import_workspace
    path = File.join(Dir.tmpdir, "dump_#{SecureRandom.hex(4)}.jsonl")
    counts = Progress::CacheDump.call(workspace_id: ws.id, path: path)

    expect(counts).to eq('robot' => 4, 'cell' => 2, 'project' => 1)
    linhas = File.readlines(path)
    expect(linhas.size).to eq(7) # 4 + 2 + 1
    expect(linhas.map { |l| JSON.parse(l)['level'] }.tally).to eq('robot' => 4, 'cell' => 2, 'project' => 1)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it '5.3 — reconciliação logo após a importação encontra ZERO divergência' do
    import_workspace
    eventos = []
    sub = ActiveSupport::Notifications.subscribe('progress_cache.divergence') { |*, p| eventos << p }
    Progress::ReconciliationJob.reconcile_workspace(ws.id)
    ActiveSupport::Notifications.unsubscribe(sub)

    expect(eventos).to be_empty
  end
end
