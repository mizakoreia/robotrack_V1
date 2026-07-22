# frozen_string_literal: true

require 'rails_helper'
require 'json'
require 'digest'

# workspace-settings 4.2/4.6 (§3.11, D-EXP) — o export: determinismo (dois exports do
# mesmo estado são byte a byte iguais, exceto `_rt.exportedAt`), contrato de topo
# igual à fixture congelada, superset (assignees + assigneeIds, advances), checksum
# reprodutível, e isolamento de tenant.
RSpec.describe Workspace::BackupExportService, :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def seed(ws_target = ws, name: 'Linha A')
    in_workspace(ws_target) do
      pessoa = Person.create!(name: 'Ana Lima', user_id: nil)
      p = Project.create!(name: name, position: 0)
      c = Cell.create!(project_id: p.id, name: 'Célula 01', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R03', application: 'Sealing', position: 0)
      t = create_task(r, desc: 'Fixação da base', position: 0, status: 'Concluído', progress: 100)
      TaskAssignee.create!(task_id: t.id, person_id: pessoa.id, workspace_id: ws_target.id)
      TaskAdvance.create!(task_id: t.id, by: pessoa.id, author_name_snapshot: 'Ana Lima',
                          from_progress: 40, to_progress: 100, comment: 'Torqueado', recorded_at: Time.utc(2026, 7, 18, 17, 2))
      TaskTemplate.create!(cat: 'A. Hardware', desc: 'Fixação da base', weight: 1, app_filters: [])
    end
  end

  def export(now: Time.utc(2026, 7, 22, 12, 0))
    in_workspace(ws) { described_class.call(workspace: Workspace.find(ws.id), now: now) }
  end

  def strip_exported_at(json)
    h = JSON.parse(json)
    h['_rt'].delete('exportedAt')
    h
  end

  it 'contrato de topo = fixture congelada (mesmas chaves)' do
    seed
    fixture = JSON.parse(File.read(Rails.root.join('spec/fixtures/backup/roboTrack_database_v2.json')))
    live = JSON.parse(export[:json])
    expect(live.keys.sort).to eq(fixture.keys.sort)
    expect(live['_rt'].keys.sort).to eq(fixture['_rt'].keys.sort)
    expect(live.dig('projects', 0, 'cells', 0, 'robots', 0, 'tasks', 0).keys.sort)
      .to eq(fixture.dig('projects', 0, 'cells', 0, 'robots', 0, 'tasks', 0).keys.sort)
  end

  it 'schemaVersion 2, superset (assignees + assigneeIds, advances) e checksum reprodutível' do
    seed
    live = JSON.parse(export[:json])
    expect(live['_rt']['schemaVersion']).to eq(2)
    task = live.dig('projects', 0, 'cells', 0, 'robots', 0, 'tasks', 0)
    expect(task['assignees']).to eq(['Ana Lima'])
    expect(task['assigneeIds'].size).to eq(1)
    expect(task['advances'].first).to include('recordedAt', 'createdAt', 'from' => 40, 'to' => 100)
    # o checksum do payload (sem _rt) é reprodutível
    payload = live.reject { |k, _| k == '_rt' }
    recomputed = Digest::SHA256.hexdigest(JSON.generate(deep_sort(payload)))
    expect(live['_rt']['checksum']).to eq(recomputed)
  end

  it 'dois exports do mesmo estado são idênticos exceto exportedAt (D-EXP)' do
    seed
    a = export(now: Time.utc(2026, 7, 22, 12, 0))
    b = export(now: Time.utc(2026, 7, 23, 9, 30)) # instante diferente
    expect(strip_exported_at(a[:json])).to eq(strip_exported_at(b[:json]))
    expect(a[:checksum]).to eq(b[:checksum])
  end

  it 'isolamento: o export de WS-1 não carrega nome/id/e-mail de WS-2' do
    seed
    other = make_workspace(owner: create(:user, name: 'Bob'))
    seed(other, name: 'SEGREDO-B')
    live = export[:json]
    expect(live).not_to include('SEGREDO-B')
    expect(JSON.parse(live)['_rt']['counts']['projects']).to eq(1)
  end

  # espelha o deep_sort do service para o recompute do checksum
  def deep_sort(node)
    case node
    when Hash  then node.keys.sort.to_h { |k| [k, deep_sort(node[k])] }
    when Array then node.map { |e| deep_sort(e) }
    else node
    end
  end
end
