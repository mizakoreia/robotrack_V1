# frozen_string_literal: true

require 'rails_helper'

# legacy-data-migration 8.1/8.2 (§2.1, D-LDM-5) — o oráculo independente de §2.1 e a amostra
# determinística/adversarial. Prova a TRADUÇÃO: o `progress_cache` importado bate, robô a
# robô, com o §2.1 recalculado em Ruby puro do arquivo. Diferença tolerada: zero.
RSpec.describe 'Legacy::SampleValidator — oráculo §2.1 e amostra adversarial', :tenancy, type: :model do
  # Canônico sintético com ≥20 robôs cobrindo TODOS os casos-limite de §2.1.
  def canonical
    robots = []
    robots << robot('R-sem-tarefas', []) # sem tarefas → 0
    robots << robot('R-so-na', Array.new(4) { |i| tk("NA#{i}", status: 'N/A') }) # só N/A → 100
    robots << robot('R-pesos', [tk('a', weight: 2, progress: 50, status: 'Em Andamento'),
                                tk('b', weight: 1, progress: 100, status: 'Concluído'),
                                tk('c', weight: 3, status: 'N/A')]) # (2*50+1*100)/3 = 66.67 → 67
    robots << robot('R-parcial', [tk('p', progress: 30, status: 'Em Andamento')]) # 30
    # o de MAIS tarefas (6):
    robots << robot('R-muitas', Array.new(6) { |i| tk("m#{i}", progress: (i.even? ? 100 : 0), status: (i.even? ? 'Concluído' : 'Pendente')) })
    # fillers até passar de 20:
    17.times { |i| robots << robot("R-fill-#{i}", [tk("f#{i}", progress: 100, status: 'Concluído')]) }

    {
      'schemaVersion' => 1, 'exportedAt' => '2024-05-01T12:00:00Z',
      'workspace' => { 'id' => 'ws-legacy-1', 'ownerUid' => 'u-dono', 'name' => 'F', 'responsibles' => [] },
      'projects' => [{ 'id' => 'p-1', 'name' => 'P', '_ord' => 1,
                       'cells' => [{ 'id' => 'c-1', 'name' => 'C', 'robots' => robots }] }]
    }
  end

  def robot(name, tasks) = { 'name' => name, 'application' => 'Handling', 'tasks' => tasks }
  def tk(desc, weight: 1, progress: 0, status: 'Pendente')
    { 'cat' => 'A', 'desc' => desc, 'weight' => weight, 'progress' => progress, 'status' => status }
  end

  def import_and_recompute
    ws = make_workspace(name: 'WS Amostra')
    run = in_workspace(ws) { LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u-dono', file_sha256: 'v' * 64) }
    Legacy::ImportService.call(canonical: canonical, run: run)
    in_workspace(ws) { Progress::BulkRecompute.call(workspace_id: ws.id) }
    ws
  end

  describe 'oráculo §2.1 (8.1) — Ruby puro do arquivo' do
    it 'calcula os casos-limite: sem tarefas = 0, só N/A = 100, ponderado com N/A ignorado' do
      by_name = canonical['projects'][0]['cells'][0]['robots'].to_h { |r| [r['name'], r] }
      expect(Legacy::SampleValidator.robot_progress(by_name['R-sem-tarefas'])).to eq(0)
      expect(Legacy::SampleValidator.robot_progress(by_name['R-so-na'])).to eq(100)
      expect(Legacy::SampleValidator.robot_progress(by_name['R-pesos'])).to eq(67) # (2*50+1*100)/3
      expect(Legacy::SampleValidator.robot_progress(by_name['R-parcial'])).to eq(30)
    end
  end

  describe 'amostra determinística e adversarial (8.2)' do
    it 'tem ≥20 robôs e inclui os casos obrigatórios' do
      sample = Legacy::SampleValidator.select_sample(canonical)
      expect(sample.size).to be >= 20
      paths = sample.map { |r| r[:legacy_path] }
      robots = Legacy::SampleValidator.enumerate_robots(canonical).to_h { |r| [r[:legacy_path], r[:robot]] }
      names = paths.map { |p| robots[p]['name'] }
      expect(names).to include('R-sem-tarefas', 'R-so-na', 'R-pesos', 'R-parcial', 'R-muitas')
    end

    it 'é reprodutível entre execuções' do
      a = Legacy::SampleValidator.select_sample(canonical).map { |r| r[:robot_id] }
      b = Legacy::SampleValidator.select_sample(canonical).map { |r| r[:robot_id] }
      expect(a).to eq(b)
    end
  end

  describe 'validação contra o progress_cache importado' do
    it 'diferença zero em toda a amostra' do
      ws = import_and_recompute
      sample = Legacy::SampleValidator.select_sample(canonical)
      in_workspace(ws) do
        expect(Legacy::SampleValidator.diffs(sample)).to be_empty
      end
    end

    it 'um único robô divergente é detectado com os dois valores' do
      ws = import_and_recompute
      sample = Legacy::SampleValidator.select_sample(canonical)
      in_workspace(ws) do
        # adultera o cache de um robô (simula import errado)
        rid = Legacy::IdDerivation.uuid("#{Legacy::IdDerivation.project_path('ws-legacy-1', 'p-1')}/cell:c-1/robot:0")
        Robot.where(id: rid).update_all(progress_cache: 42)
        diffs = Legacy::SampleValidator.diffs(sample)
        expect(diffs).not_to be_empty
        expect(diffs.first).to include(:expected, :actual)
      end
    end
  end
end
