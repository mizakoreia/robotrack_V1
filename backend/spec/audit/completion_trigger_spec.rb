# frozen_string_literal: true

require 'rails_helper'

# audit-log 4.1–4.3 (§2.2/§2.8, Decisão 3) — o gatilho automático: a conclusão a
# 100% grava UM registro de auditoria, na MESMA transação do avanço. Abaixo de 100,
# N/A e reabertura NÃO gravam. Reenvio idempotente (mesmo uuid) mantém 1 registro. Se
# o INSERT do log falhar, o avanço faz rollback (nada de conclusão sem registro).
RSpec.describe 'audit-log — gatilho de conclusão a 100%', :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  let(:setup) do
    in_workspace(ws) do
      Person.create!(name: 'Ana Dona', user_id: ana.id)
      projeto = Project.create!(name: 'L')
      celula = Cell.create!(project_id: projeto.id, name: 'C')
      robo = Robot.create!(cell_id: celula.id, name: 'R-014')
      tarefa = create_task(robo, desc: 'Power On', progress: 45, status: 'Em Andamento', position: 0)
      { tarefa: tarefa, robo: robo }
    end
  end

  def context
    in_workspace(ws) { Authorization::Context.new(user: ana, workspace: Workspace.find(ws.id)) }
  end

  def call(**kwargs)
    in_workspace(ws) { TaskAdvances::CreateService.new(context: context).call(**kwargs) }
  end

  def audit_count(event: 'task_completed')
    in_workspace(ws) { AuditLog.where(event_type: event).count }
  end

  def audit_rows
    in_workspace(ws) { AuditLog.where(event_type: 'task_completed').to_a }
  end

  describe 'grava 1 registro na conclusão (4.1)' do
    it '45 → 100 cria exatamente 1 task_completed com a msg renderizada' do
      s = setup
      expect { call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0) }
        .to change { audit_count }.from(0).to(1)
      log = audit_rows.first
      # o auto_assign atribui o autor → aparece em %{assignees}
      expect(log.msg).to eq('Em [R-014], Ana Dona concluiu a tarefa "Power On" com 100%.')
      expect(log.by_name).to eq('Ana Dona')
      expect(log.ts_local).to match(%r{\A\d{2}/\d{2}/\d{4} \d{2}:\d{2}\z})
    end
  end

  describe 'NÃO grava fora da conclusão (4.2)' do
    it '45 → 90 (Em Andamento, com comentário) não gera registro' do
      s = setup
      expect { call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 90, comment: 'faltou teste', lock_version: 0) }
        .not_to change { audit_count }
    end

    it 'transição para N/A não gera registro' do
      s = setup
      expect { call(task_id: s[:tarefa].id, id: SecureRandom.uuid, status: 'N/A', lock_version: 0) }
        .not_to change { audit_count }
    end

    it 'reabertura (100 → 50) não gera um segundo registro' do
      s = setup
      call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0)
      expect(audit_count).to eq(1)
      lv = in_workspace(ws) { Task.find(s[:tarefa].id).lock_version }
      expect { call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 50, comment: 'reabrir', lock_version: lv) }
        .not_to change { audit_count }
    end
  end

  describe 'idempotência e atomicidade (4.3, Decisão 3)' do
    it 'reenviar o MESMO uuid (replay) mantém 1 registro' do
      s = setup
      uuid = SecureRandom.uuid
      call(task_id: s[:tarefa].id, id: uuid, progress: 100, lock_version: 0)
      expect(audit_count).to eq(1)
      # replay: mesmo uuid → 200 sem re-rodar a transação
      r = call(task_id: s[:tarefa].id, id: uuid, progress: 100, lock_version: 0)
      expect(r[:data][:replay]).to be(true)
      expect(audit_count).to eq(1)
    end

    it 'se o INSERT do log falhar, o avanço faz rollback (tarefa em 45, sem avanço, sem log)' do
      s = setup
      allow(AuditLog::RecordService).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, 'boom')
      expect { call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0) }
        .to raise_error(ActiveRecord::StatementInvalid)
      t = in_workspace(ws) { Task.find(s[:tarefa].id) }
      expect([t.status, t.progress]).to eq(['Em Andamento', 45])
      expect(in_workspace(ws) { TaskAdvance.where(task_id: s[:tarefa].id).count }).to eq(0)
      expect(audit_count).to eq(0)
    end
  end
end
