# frozen_string_literal: true

require 'rails_helper'
require 'pg'
require 'shellwords'
require 'securerandom'

# audit-log 9.2 (§4.1 inv. 3, Decisão 1) — a suíte de CONTORNO, o capstone: reúne
# TODOS os vetores de mutação/exclusão de um registro de auditoria num só lugar. Se
# QUALQUER um passar, a imutabilidade é teatro. A invariante 3 é a única cujo
# adversário é o próprio dono do dado — logo os vetores incluem o console da
# aplicação (papel `robotrack_app`), o papel DONO (`robotrack_migrator`) e o
# SUPERUSER. As três camadas (REVOKE + RLS-sem-policy + trigger) fecham todos.
RSpec.describe 'audit-log — suíte de contorno da imutabilidade (§4.1 inv. 3)', :tenancy, type: :request do
  let(:conn)  { ActiveRecord::Base.connection }
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def q(v) = conn.quote(v)

  let(:log_id) do
    id = SecureRandom.uuid
    in_workspace(ws) do
      conn.execute(<<~SQL)
        INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name)
        VALUES (#{q(id)}, #{q(ws.id)}, 'task_completed', 1, 'linha imutável', now(), 'x', 'Ana Dona')
      SQL
    end
    id
  end

  def surviving_msg
    in_workspace(ws) { conn.select_value("SELECT msg FROM audit_logs WHERE id = #{q(log_id)}") }
  end

  describe 'papel da aplicação (robotrack_app) — camada 1 (REVOKE)' do
    it 'UPDATE cru é permission denied' do
      log_id
      expect { in_workspace(ws) { conn.execute("UPDATE audit_logs SET msg='x' WHERE id=#{q(log_id)}") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      expect(surviving_msg).to eq('linha imutável')
    end

    it 'DELETE cru é permission denied' do
      log_id
      expect { in_workspace(ws) { conn.execute("DELETE FROM audit_logs WHERE id=#{q(log_id)}") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      expect(surviving_msg).to eq('linha imutável')
    end

    it 'AR update_column / update_all / delete_all pela app não mutam nem apagam' do
      log_id
      rec = in_workspace(ws) { AuditLog.find(log_id) }
      # update_column bate no guard readonly? do model (camada amigável) ANTES do banco
      expect { rec.update_column(:msg, 'x') }.to raise_error(ActiveRecord::ReadOnlyRecord)
      # update_all/delete_all pulam a instância e batem no banco → REVOKE (permission denied)
      expect { in_workspace(ws) { AuditLog.where(id: log_id).update_all(msg: 'x') } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      expect { in_workspace(ws) { AuditLog.where(id: log_id).delete_all } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      expect(surviving_msg).to eq('linha imutável')
    end

    it 'save de registro carregado levanta ReadOnlyRecord (a mensagem amigável, antes do banco)' do
      log_id
      rec = in_workspace(ws) { AuditLog.find(log_id) }
      rec.msg = 'x'
      expect { rec.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe 'papel DONO (robotrack_migrator) — camada 3 (RLS sem policy de mutação)' do
    it 'UPDATE/DELETE atingem 0 linhas (sem policy de UPDATE/DELETE, a RLS filtra antes)' do
      log_id
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      mconn = PG.connect(host: cfg[:host] || 'localhost', dbname: cfg[:database],
                         user: 'robotrack_migrator', password: 'mig_dev_pw')
      mconn.exec("SELECT set_config('app.current_workspace_id', #{q(ws.id)}, false)")
      expect(mconn.exec("UPDATE audit_logs SET msg='x' WHERE id=#{q(log_id)}").cmd_tuples).to eq(0)
      expect(mconn.exec("DELETE FROM audit_logs WHERE id=#{q(log_id)}").cmd_tuples).to eq(0)
      expect(surviving_msg).to eq('linha imutável')
    ensure
      mconn&.close
    end
  end

  describe 'SUPERUSER (ignora a RLS) — camada 2 (trigger)' do
    it 'UPDATE e DELETE são barrados pela trigger append-only' do
      unless system('su - postgres -c true >/dev/null 2>&1')
        skip 'requer superuser via `su - postgres` (ambiente local)'
      end
      id = log_id
      db = ActiveRecord::Base.connection_db_config.configuration_hash[:database]
      run = ->(sql) { `su - postgres -c #{Shellwords.escape("psql -d #{db} -c #{Shellwords.escape(sql)}")} 2>&1` }
      expect(run.call("UPDATE audit_logs SET msg='hack' WHERE id='#{id}'")).to match(/append-only/)
      expect(run.call("DELETE FROM audit_logs WHERE id='#{id}'")).to match(/append-only/)
      expect(surviving_msg).to eq('linha imutável')
    end
  end
end
