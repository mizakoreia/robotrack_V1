# frozen_string_literal: true

require 'rails_helper'

# audit-log 3.3/3.4/3.6 (§2.8, Decisão 3/4/5/6, §1.4) — o service de escrita: renderiza
# `msg`/`ts_local` congelados no INSERT, grava `format_version`, snapshota o autor
# (`by_person_id`+`by_name`), aceita autor irresolúvel (importação legada), e recusa
# `by_name` vazio. Chamado de dentro do contexto de tenant (RLS INSERT WITH CHECK).
RSpec.describe AuditLog::RecordService, :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Ribeiro') }
  let(:ws)    { make_workspace(owner: owner) }
  let(:ana)   { in_workspace(ws) { Person.create!(name: 'Ana Ribeiro', user_id: owner.id) } }

  def record(**over)
    defaults = {
      workspace: ws, event: :task_completed, by: ana,
      payload: { robot_name: 'R-014', task_desc: 'Solda ponto 3', assignee_names: ['Ana Ribeiro'] }
    }
    in_workspace(ws) { described_class.record!(**defaults.merge(over)) }
  end

  describe 'task_completed — renderização e snapshot' do
    it 'renderiza a msg da format string v1 e grava format_version=1' do
      log = record
      expect(log.msg).to eq('Em [R-014], Ana Ribeiro concluiu a tarefa "Solda ponto 3" com 100%.')
      expect(log.event_type).to eq('task_completed')
      expect(log.format_version).to eq(1)
    end

    it 'snapshota o autor: by_person_id da Person, by_name copiado' do
      log = record
      expect(log.by_person_id).to eq(ana.id)
      expect(log.by_name).to eq('Ana Ribeiro')
    end

    it 'dois responsáveis unem no %{assignees}, com o verbo no singular do v1' do
      log = record(by: ana, payload: { robot_name: 'R-07', task_desc: 'TCP', assignee_names: ['Ana Ribeiro', 'Bruno Sá'] })
      expect(log.msg).to eq('Em [R-07], Ana Ribeiro, Bruno Sá concluiu a tarefa "TCP" com 100%.')
    end

    it 'ts_local é congelado no fuso do workspace (texto estável, não recalculado na leitura)' do
      fixed = Time.utc(2026, 7, 18, 20, 2) # 17:02 em America/Sao_Paulo (UTC-3)
      log = in_workspace(ws) do
        described_class.record!(workspace: ws, event: :task_completed, by: ana, now: fixed,
                                payload: { robot_name: 'R', task_desc: 'T', assignee_names: ['Ana Ribeiro'] })
      end
      expect(log.ts_local).to eq('18/07/2026 17:02')
    end

    it 'renomear a Person depois NÃO reescreve by_name (snapshot imutável, D10)' do
      log = record
      in_workspace(ws) do
        Person.where(id: ana.id).update_all(name: 'Ana R. Souza')
        expect(log.reload.by_name).to eq('Ana Ribeiro') # reload sob contexto (RLS)
      end
    end

    it 'o payload de máquina guarda os dados, sem :id nem :by_name' do
      log = record(payload: { id: SecureRandom.uuid, robot_name: 'R-1', task_desc: 'T', assignee_names: ['Ana Ribeiro'], by_name: 'ignorar' })
      expect(log.payload).to include('robot_name' => 'R-1', 'task_desc' => 'T')
      expect(log.payload).not_to have_key('id')
      expect(log.payload).not_to have_key('by_name')
    end
  end

  describe 'workspace_reset — renderização' do
    it 'renderiza projects_count e usa by_name' do
      log = record(event: :workspace_reset, by: ana, payload: { projects_count: 3 })
      expect(log.msg).to eq('Ana Ribeiro executou o reset de fábrica do workspace. Projetos removidos: 3.')
      expect(log.event_type).to eq('workspace_reset')
    end
  end

  describe 'autor irresolúvel e by_name vazio (§1.4, 3.6)' do
    it 'autor sem Person (by: nil) grava by_person_id NULL e by_name do payload' do
      log = record(by: nil, payload: { robot_name: 'R', task_desc: 'T', assignee_names: [], by_name: '(nota anterior)' })
      expect(log.by_person_id).to be_nil
      expect(log.by_name).to eq('(nota anterior)')
    end

    it 'by_name vazio (sem autor e sem payload) é RECUSADO (NOT NULL / CHECK)' do
      expect do
        record(by: nil, payload: { robot_name: 'R', task_desc: 'T', assignee_names: [] })
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'evento inválido levanta ArgumentError antes de tocar o banco' do
      expect do
        record(event: :task_deleted, payload: {})
      end.to raise_error(ArgumentError, /inválido/)
    end
  end
end
