# frozen_string_literal: true

require 'rails_helper'
require 'json'

# legacy-data-migration 5.8 (§1.4, §2.1, D-LDM-7) — a prova fim-a-fim: importa a fixture
# canônica e afirma a contagem EXATA por tabela, incluindo os ZEROS esperados (projeto sem
# cells = 0 células, robô sem tasks = 0 tarefas + progress_cache 0) e a quarentena. O modo
# de falha que isto guarda é o importador engolir silenciosamente um nível da hierarquia.
RSpec.describe 'Legacy::ImportService — import fim a fim da fixture canônica', :tenancy, type: :model do
  let(:canonical) do
    JSON.parse(File.read(Rails.root.join('spec/fixtures/legacy/canonical_v1.json'), encoding: 'UTF-8'))
  end

  def import!(ws)
    run = in_workspace(ws) do
      LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u-dono', file_sha256: 'z' * 64)
    end
    report = Legacy::ImportService.call(canonical: canonical, run: run)
    [run, report]
  end

  it 'importa a hierarquia com as contagens exatas, incluindo os zeros e a quarentena' do
    ws = make_workspace(name: 'Fábrica Destino')
    _run, report = import!(ws)

    in_workspace(ws) do
      expect(Project.count).to eq(4)
      expect(Cell.count).to eq(3)          # p-1: 2, p-2: 1, p-3/p-4: 0
      expect(Robot.count).to eq(4)         # c-1: 3 (2 homônimos distintos), p-2: 1 (R10 quarentenado)
      expect(Task.count).to eq(8)          # r-1: 5 (2 quarentenadas), R05-sem-id: 1, R09: 2
      expect(Person.count).to eq(4)        # Ana, Bruno, João (colapsa caixa), Dona
      expect(TaskAssignee.count).to eq(3)  # Ana(t1), João(R05-sem-id), João(R09-Montagem)
      expect(TaskAdvance.count).to eq(4)   # t1 history(1) + t3 obs-legado(1) + t7 history(2)
      expect(TaskTemplate.count).to eq(4)
      expect(Notification.count).to eq(1)
      expect(AuditLog.count).to eq(1)

      # Zeros estruturais (o nível existe, mas vazio).
      p3 = Project.find(Legacy::IdDerivation.project_id('ws-legacy-1', 'p-3'))
      expect(Cell.where(project_id: p3.id).count).to eq(0)
      r2 = Robot.find(Legacy::IdDerivation.robot_id('ws-legacy-1', 'p-1', 'c-1', 'r-2'))
      expect(Task.where(robot_id: r2.id).count).to eq(0)
      expect(r2.progress_cache).to eq(0)   # robô sem tarefas = 0 (§2.1)
    end
  end

  it 'colapsa "João Silva"/"joão silva" numa Person e aponta as duas tarefas para ela' do
    ws = make_workspace(name: 'WS Homônimo')
    import!(ws)
    in_workspace(ws) do
      joao_id = Legacy::IdDerivation.person_id('ws-legacy-1', 'João Silva')
      expect(Person.where(id: joao_id)).to be_present
      expect(TaskAssignee.where(person_id: joao_id).count).to eq(2)
    end
  end

  it 'não cria nenhuma Person sentinela e reporta a quarentena esperada' do
    ws = make_workspace(name: 'WS Report')
    _run, report = import!(ws)

    in_workspace(ws) do
      expect(Person.where("btrim(lower(name)) = 'não atribuído'")).to be_empty
    end
    reasons = report.quarantine.map { |q| q['reason'] }
    expect(reasons).to include('application_fora_do_enum', 'progress_fora_da_faixa',
                               'status_fora_do_enum', 'obs_descartado_historico_presente')
    warns = report.warnings.map { |w| w['reason'] }
    expect(warns).to include('app_filters_divergentes', 'status_derivado_de_progresso')
  end

  it 'segundo run cria zero (ON CONFLICT DO NOTHING) e mantém as contagens' do
    ws = make_workspace(name: 'WS Idem')
    run1, = import!(ws)
    counts = in_workspace(ws) { [Project.count, Robot.count, Task.count, Person.count, TaskAdvance.count] }

    report2 = Legacy::ImportService.call(canonical: canonical, run: run1)

    expect(report2.created.values.sum).to eq(0)
    after = in_workspace(ws) { [Project.count, Robot.count, Task.count, Person.count, TaskAdvance.count] }
    expect(after).to eq(counts)
  end
end
