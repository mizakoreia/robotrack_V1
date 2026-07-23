# frozen_string_literal: true

require 'rails_helper'

# legacy-data-migration 6.5 (§1.4, §2.2, D-LDM-4, D-LDM-7) — um spec por REGRA de §1.4,
# cada um exercitando o caminho POSITIVO e o NEGATIVO. O erro histórico é testar só o
# caminho feliz das três regras e descobrir o resto em produção. O comportamento mora no
# `Legacy::ImportService` (construído em G5); aqui está a prova granular de cada regra.
RSpec.describe 'Legacy::ImportService — as 3 regras de §1.4', :tenancy, type: :model do
  # Canônico mínimo de 1 projeto/1 célula/1 robô com as tarefas dadas.
  def canonical(tasks:, app: 'Handling', responsibles: [], exported_at: '2024-05-01T12:00:00Z', lws: 'ws-legacy-1')
    {
      'schemaVersion' => 1, 'exportedAt' => exported_at,
      'workspace' => { 'id' => lws, 'ownerUid' => 'u-dono', 'name' => 'F', 'responsibles' => responsibles },
      'projects' => [{ 'id' => 'p-1', 'name' => 'P', '_ord' => 1,
                       'cells' => [{ 'id' => 'c-1', 'name' => 'C',
                                     'robots' => [{ 'id' => 'r-1', 'name' => 'R01', 'application' => app, 'tasks' => tasks }] }] }]
    }
  end

  def import(doc)
    ws = make_workspace(name: "WS #{SecureRandom.hex(3)}")
    run = in_workspace(ws) do
      LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u-dono', file_sha256: SecureRandom.hex(32))
    end
    report = Legacy::ImportService.call(canonical: doc, run: run)
    [ws, report]
  end

  def task(desc, **over)
    { 'cat' => 'A. Hardware', 'desc' => desc, 'weight' => 1, 'progress' => 0, 'status' => 'Pendente' }.merge(over.transform_keys(&:to_s))
  end

  # === Regra 1: cascata de responsáveis (§1.4 item 1, 6.1) ===
  describe 'cascata de responsáveis' do
    it 'assignees presente VENCE resp (positivo) e resp não é consultado' do
      ws, = import(canonical(tasks: [task('T', assignees: ['Maria'], resp: 'João')]))
      in_workspace(ws) do
        expect(Person.pluck(:name)).to include('Maria')
        expect(Person.pluck(:name)).not_to include('João')
        expect(TaskAssignee.count).to eq(1)
      end
    end

    it 'assignees VAZIO é resposta, não ausência — PARA a cascata (negativo)' do
      ws, = import(canonical(tasks: [task('T', assignees: [], resp: 'Maria')]))
      in_workspace(ws) do
        expect(TaskAssignee.count).to eq(0)
        expect(Person.pluck(:name)).not_to include('Maria') # resp nem consultado
      end
    end

    it 'resp usado quando assignees ausente; nenhum dos dois = zero sem falhar' do
      ws, = import(canonical(tasks: [task('T1', resp: 'Carlos'), task('T2')]))
      in_workspace(ws) do
        expect(Person.pluck(:name)).to include('Carlos')
        expect(TaskAssignee.count).to eq(1)
      end
    end
  end

  # === Regra 2: obs → avanço legado (§1.4 item 2, 6.2) ===
  describe 'obs vira avanço legado' do
    it 'obs com history vazio vira a 1ª entrada legada com recorded_at do _updatedAt (positivo)' do
      doc = canonical(tasks: [task('T', progress: 50, status: 'Em Andamento',
                                    obs: 'Cabo pendente', history: [], _updatedAt: '2024-03-11T14:02:00Z')])
      ws, = import(doc)
      in_workspace(ws) do
        adv = TaskAdvance.where(legacy: true)
        expect(adv.count).to eq(1)
        a = adv.first
        expect(a.by).to be_nil
        expect(a.author_name_snapshot).to eq('(nota anterior)')
        expect([a.from_progress, a.to_progress]).to eq([0, 0])
        expect(a.comment).to eq('Cabo pendente')
        expect(a.recorded_at).to eq(Time.parse('2024-03-11T14:02:00Z'))
      end
    end

    it 'obs com history PRESENTE vai para quarentena; history entra, nada legacy (negativo)' do
      doc = canonical(tasks: [task('T', progress: 20, status: 'Em Andamento', obs: 'revisar', history: [
        { 'from' => 0, 'to' => 10, 'comment' => 'i', 'byName' => 'Ana', 'ts' => '2024-04-01T10:00:00Z' },
        { 'from' => 10, 'to' => 20, 'comment' => 's', 'byName' => 'Ana', 'ts' => '2024-04-02T10:00:00Z' }
      ])])
      ws, report = import(doc)
      in_workspace(ws) do
        expect(TaskAdvance.count).to eq(2)
        expect(TaskAdvance.where(legacy: true).count).to eq(0)
      end
      expect(report.quarantine_reason?('obs_descartado_historico_presente')).to be(true)
    end

    it 'recorded_at é DETERMINÍSTICO entre dois exports/bancos distintos (nunca Time.now)' do
      # Dois exports distintos (lws diferentes → ids distintos, sem colisão de PK global) com
      # o MESMO _updatedAt: se `recorded_at` viesse de Time.now os dois runs divergiriam.
      opts = { progress: 50, status: 'Em Andamento', obs: 'nota', history: [], _updatedAt: '2024-03-11T14:02:00Z' }
      ws1, = import(canonical(lws: 'ws-A', tasks: [task('T', **opts)]))
      ws2, = import(canonical(lws: 'ws-B', tasks: [task('T', **opts)]))
      r1 = in_workspace(ws1) { TaskAdvance.where(legacy: true).first.recorded_at }
      r2 = in_workspace(ws2) { TaskAdvance.where(legacy: true).first.recorded_at }
      expect(r1).to eq(r2)
      expect(r1).to eq(Time.parse('2024-03-11T14:02:00Z'))
    end

    it 'obs vazio não gera avanço' do
      ws, = import(canonical(tasks: [task('T', obs: '', history: [])]))
      in_workspace(ws) { expect(TaskAdvance.count).to eq(0) }
    end
  end

  # === Regra 3: status↔progresso incoerentes + quarentena (§2.2, D-LDM-7, 6.3/6.4) ===
  describe 'coerência status/progresso e quarentena' do
    it 'Concluído com progress 80 → importa 80 + Em Andamento (progresso vence) (positivo)' do
      ws, report = import(canonical(tasks: [task('T', progress: 80, status: 'Concluído')]))
      in_workspace(ws) do
        t = Task.first
        expect(t.progress).to eq(80)
        expect(t.status).to eq('Em Andamento')
      end
      expect(report.warning_reason?('status_derivado_de_progresso')).to be(true)
    end

    it 'progress 150 NÃO vira 100: a tarefa não entra, as irmãs sim (negativo)' do
      ws, report = import(canonical(tasks: [task('Ruim', progress: 150, status: 'Em Andamento'), task('Boa', progress: 30, status: 'Em Andamento')]))
      in_workspace(ws) do
        expect(Task.pluck(:desc)).to eq(['Boa'])
        expect(Task.where(progress: 100).count).to eq(0)
      end
      expect(report.quarantine_reason?('progress_fora_da_faixa')).to be(true)
    end

    it 'status fora do enum quarentena a tarefa, irmãs entram' do
      ws, report = import(canonical(tasks: [task('Ruim', status: 'Em Análise'), task('Boa')]))
      in_workspace(ws) { expect(Task.pluck(:desc)).to eq(['Boa']) }
      expect(report.quarantine_reason?('status_fora_do_enum')).to be(true)
    end

    it 'application fora do enum quarentena o robô E suas tarefas' do
      ws, report = import(canonical(app: 'Paletização', tasks: [task('T')]))
      in_workspace(ws) do
        expect(Robot.count).to eq(0)
        expect(Task.count).to eq(0)
      end
      expect(report.quarantine_reason?('application_fora_do_enum')).to be(true)
    end
  end
end
