# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'

# audit-log 7.1–7.3 (D12, Decisão 7) — a FRONTEIRA com o reset de fábrica, provada
# do LADO do audit-log. O `Workspace::FactoryResetService` é de `workspace-settings`
# (ainda não existe), então SIMULAMOS a transação do reset (cascade delete da
# hierarquia + o registro do evento) para provar as duas metades de D12:
#   1. o log SOBREVIVE ao cascade delete (sem FK para hierarquia) e cresce em 1,
#      com os anteriores byte-idênticos;
#   2. a variante ANTIGA (que apagava `audit_logs`) é IMPOSSÍVEL de executar — o
#      `DELETE FROM audit_logs` bate no REVOKE e faz a transação inteira dar rollback.
# A integração com o reset REAL (12→13 pelo serviço) fica para `workspace-settings`.
RSpec.describe 'audit-log — fronteira com o reset de fábrica (D12)', :tenancy, type: :request do
  let(:conn)  { ActiveRecord::Base.connection }
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  let(:person) { in_workspace(ws) { Person.create!(name: 'Ana Dona', user_id: owner.id) } }

  def q(v) = conn.quote(v)

  # 3 projetos → célula → robô → tarefa (sem avanços, p/ o cascade delete fluir).
  def seed_hierarchy(n = 3)
    in_workspace(ws) do
      n.times do |i|
        p = Project.create!(name: "P#{i}", position: i)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
        create_task(r, desc: 'T', position: 0, status: 'Pendente', progress: 0)
      end
    end
  end

  # N registros de auditoria "históricos" (task_completed), via INSERT cru legítimo.
  def seed_logs(n, base: Time.utc(2026, 7, 1, 12, 0))
    in_workspace(ws) do
      values = Array.new(n) do |i|
        "(#{q(SecureRandom.uuid)}, #{q(ws.id)}, 'task_completed', 1, #{q("registro #{i}")}, " \
          "#{q(base + i.seconds)}, '01/07/2026 09:00', 'Ana Dona', '{}'::jsonb)"
      end.join(',')
      conn.execute(<<~SQL)
        INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name, payload)
        VALUES #{values}
      SQL
    end
  end

  def audit_snapshot
    in_workspace(ws) { AuditLog.order(:ts).pluck(:id, :msg, :ts_local) }
  end

  def project_count = in_workspace(ws) { Project.count }
  def audit_count   = in_workspace(ws) { AuditLog.count }

  describe 'o log sobrevive ao reset e registra que ele ocorreu (7.1/7.2)' do
    it 'cascade delete da hierarquia + registro do reset: 12 → 13, os 12 anteriores byte-idênticos' do
      person
      seed_hierarchy(3)
      seed_logs(12)
      antes = audit_snapshot
      expect(antes.size).to eq(12)

      # SIMULAÇÃO da transação atômica do reset (o que workspace-settings fará):
      in_workspace(ws) do
        ActiveRecord::Base.transaction do
          conn.execute("DELETE FROM projects WHERE workspace_id = #{q(ws.id)}") # cascateia célula/robô/tarefa
          AuditLog::RecordService.record!(
            workspace: ws, event: :workspace_reset, by: person, payload: { projects_count: 3 }
          )
        end
      end

      expect(project_count).to eq(0)          # hierarquia apagada
      depois = audit_snapshot
      expect(depois.size).to eq(13)           # +1 (o registro do reset)
      # os 12 anteriores intactos, byte a byte
      expect(depois.first(12)).to eq(antes)
      novo = in_workspace(ws) { AuditLog.order(:ts).last }
      expect(novo.event_type).to eq('workspace_reset')
      expect(novo.msg).to eq('Ana Dona executou o reset de fábrica do workspace. Projetos removidos: 3.')
    end
  end

  describe 'a variante antiga (apagar auditoria) é impossível de executar (7.3)' do
    it 'DELETE FROM audit_logs dentro da transação do reset → rollback integral' do
      person
      seed_hierarchy(3)
      seed_logs(12)

      expect do
        in_workspace(ws) do
          ActiveRecord::Base.transaction do
            conn.execute("DELETE FROM projects WHERE workspace_id = #{q(ws.id)}")
            # o passo que a contradição herdada exigia — barrado pelo REVOKE do app
            conn.execute("DELETE FROM audit_logs WHERE workspace_id = #{q(ws.id)}")
          end
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)

      # rollback integral: os 3 projetos e os 12 registros continuam lá.
      expect(project_count).to eq(3)
      expect(audit_count).to eq(12)
    end
  end
end
