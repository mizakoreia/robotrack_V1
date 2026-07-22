# frozen_string_literal: true

require 'rails_helper'
require 'pg'
require 'securerandom'
require 'shellwords'

# audit-log G1 (§1.1, §2.8, §4.1 inv. 3, Decisão 1/2/7) — o ESQUEMA de audit_logs
# provado CONTORNANDO o ActiveRecord, por SQL cru: é por esse caminho (console,
# importador, psql) que as garantias serão exercidas. As três camadas de
# imutabilidade (REVOKE do app, trigger para o dono, RLS sem UPDATE/DELETE), o
# particionamento por ts, o roteamento de partição, e a fronteira com o reset
# (sem FK para hierarquia, workspaces ON DELETE RESTRICT).
RSpec.describe 'audit_logs — esquema e imutabilidade', :tenancy, type: :request do
  let(:conn)  { ActiveRecord::Base.connection }
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def q(v) = conn.quote(v)

  # INSERT legítimo (append) pelo papel de app, sob contexto de tenant (RLS libera
  # INSERT com workspace_id casando o app.current_workspace_id).
  def insert_log(workspace_id:, id: SecureRandom.uuid, ts: Time.current, event: 'task_completed', by_name: 'Ana Dona')
    conn.execute(<<~SQL)
      INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name, payload)
      VALUES (#{q(id)}, #{q(workspace_id)}, #{q(event)}, 1, 'linha de log', #{q(ts)}, '01/01 00:00', #{q(by_name)}, '{}'::jsonb)
    SQL
    id
  end

  describe 'privilégio do papel de app (1.3, Decisão 1 camada 1)' do
    it 'robotrack_app NÃO tem UPDATE nem DELETE sobre audit_logs' do
      up = conn.select_value("SELECT has_table_privilege(current_user, 'audit_logs', 'UPDATE')")
      del = conn.select_value("SELECT has_table_privilege(current_user, 'audit_logs', 'DELETE')")
      ins = conn.select_value("SELECT has_table_privilege(current_user, 'audit_logs', 'INSERT')")
      sel = conn.select_value("SELECT has_table_privilege(current_user, 'audit_logs', 'SELECT')")
      expect(up).to be(false)
      expect(del).to be(false)
      expect(ins).to be(true) # append continua permitido
      expect(sel).to be(true)
    end

    it 'ImmutabilityGuard.violated? é false rodando como o papel de app (boot não aborta)' do
      expect(AuditLog::ImmutabilityGuard.violated?(conn)).to be(false)
    end
  end

  describe 'INSERT legítimo, NOT NULL e roteamento de partição (2.1/2.2)' do
    it 'workspace_id é NOT NULL no esquema e um INSERT sem ele é recusado' do
      not_nullable = conn.select_value(<<~SQL)
        SELECT is_nullable FROM information_schema.columns
        WHERE table_name = 'audit_logs' AND column_name = 'workspace_id'
      SQL
      expect(not_nullable).to eq('NO')

      # Pelo app, um workspace_id nulo é recusado (NOT NULL e/ou WITH CHECK da RLS —
      # nulo nunca casa o app.current_workspace_id).
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO audit_logs (id, event_type, format_version, msg, ts, ts_local, by_name)
            VALUES (#{q(SecureRandom.uuid)}, 'task_completed', 1, 'x', now(), 'x', 'Ana')
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /null value|row-level security|not-null/)
      end
    end

    it 'uma linha com ts do mês corrente reside na partição audit_logs_AAAA_MM' do
      id = in_workspace(ws) { insert_log(workspace_id: ws.id, ts: Time.current) }
      part = in_workspace(ws) do
        conn.select_value("SELECT tableoid::regclass::text FROM audit_logs WHERE id = #{q(id)}")
      end
      expect(part).to eq("audit_logs_#{Time.current.utc.strftime('%Y_%m')}")
    end
  end

  describe 'RLS: SELECT e INSERT por workspace, sem UPDATE/DELETE (2.3)' do
    it 'a sessão do workspace A conta só as linhas de A' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      in_workspace(ws)    { 3.times { insert_log(workspace_id: ws.id) } }
      in_workspace(other) { 5.times { insert_log(workspace_id: other.id) } }
      seen_a = in_workspace(ws)    { conn.select_value('SELECT COUNT(*) FROM audit_logs').to_i }
      seen_b = in_workspace(other) { conn.select_value('SELECT COUNT(*) FROM audit_logs').to_i }
      expect(seen_a).to eq(3)
      expect(seen_b).to eq(5)
    end

    it 'INSERT com workspace_id de OUTRO tenant falha no WITH CHECK' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      expect do
        in_workspace(ws) { insert_log(workspace_id: other.id) }
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security|violates/)
    end

    it 'SELECT DIRETO numa partição não vaza cross-tenant (RLS por partição, não só no parent)' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      in_workspace(ws)    { 3.times { insert_log(workspace_id: ws.id) } }
      in_workspace(other) { 5.times { insert_log(workspace_id: other.id) } }
      part = "audit_logs_#{Time.current.utc.strftime('%Y_%m')}"
      # a sessão de A, consultando a PARTIÇÃO diretamente, vê só as 3 de A.
      seen = in_workspace(ws) { conn.select_value("SELECT COUNT(*) FROM #{part}").to_i }
      expect(seen).to eq(3)
    end
  end

  # Reconciliação (registrada no EXECUCAO G1): a RLS SEM política de UPDATE/DELETE
  # já filtra o papel DONO (migrator) para 0 linhas ANTES da trigger — a trigger é
  # o backstop EXCLUSIVO do superuser, que ignora a RLS. Provamos as duas camadas.
  describe 'imutabilidade — camada RLS (dono) e camada trigger (superuser) (2.4/2.5)' do
    it 'UPDATE/DELETE como robotrack_migrator (dono) atinge 0 linhas (RLS sem policy de mutação); a linha sobrevive' do
      id = in_workspace(ws) { insert_log(workspace_id: ws.id) }

      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      mconn = PG.connect(
        host: cfg[:host] || 'localhost', dbname: cfg[:database],
        user: ENV.fetch('MIGRATOR_DB_USER', 'robotrack_migrator'),
        password: ENV.fetch('MIGRATOR_DB_PASSWORD', 'mig_dev_pw')
      )
      mconn.exec("SELECT set_config('app.current_workspace_id', #{q(ws.id)}, false)")

      # o dono VÊ a linha (policy de SELECT), mas UPDATE/DELETE não têm policy →
      # 0 linhas afetadas, sem erro. A imutabilidade se mantém por omissão.
      expect(mconn.exec("SELECT COUNT(*) FROM audit_logs WHERE id = #{q(id)}").getvalue(0, 0)).to eq('1')
      expect(mconn.exec("UPDATE audit_logs SET msg = 'adulterado' WHERE id = #{q(id)}").cmd_tuples).to eq(0)
      expect(mconn.exec("DELETE FROM audit_logs WHERE id = #{q(id)}").cmd_tuples).to eq(0)
    ensure
      mconn&.close
    end

    it 'a trigger barra UPDATE e DELETE de um SUPERUSER (que ignora a RLS); INSERT segue permitido' do
      unless system('su - postgres -c true >/dev/null 2>&1')
        skip 'requer superuser via `su - postgres` (ambiente local); a trigger está anexada (verificado em pg_trigger)'
      end
      id = in_workspace(ws) { insert_log(workspace_id: ws.id) } # commit (modo truncation)
      db = ActiveRecord::Base.connection_db_config.configuration_hash[:database]

      def as_super(db, sql) = `su - postgres -c #{Shellwords.escape("psql -d #{db} -c #{Shellwords.escape(sql)}")} 2>&1`

      expect(as_super(db, "UPDATE audit_logs SET msg='hack' WHERE id='#{id}'")).to match(/append-only/)
      expect(as_super(db, "DELETE FROM audit_logs WHERE id='#{id}'")).to match(/append-only/)
      # A linha sobrevive intacta.
      survived = in_workspace(ws) { conn.select_value("SELECT msg FROM audit_logs WHERE id = #{q(id)}") }
      expect(survived).to eq('linha de log')
      # A trigger não barra escrita legítima: INSERT do superuser passa.
      wid = ws.id
      ins = as_super(db, "INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name) " \
                         "VALUES ('#{SecureRandom.uuid}', '#{wid}', 'task_completed', 1, 'ok', now(), 'x', 'Ana')")
      expect(ins).to match(/INSERT 0 1/)
    end
  end

  describe 'fronteira com o reset de fábrica (Decisão 7/D12)' do
    it 'audit_logs NÃO tem FK para projects/cells/robots/tasks' do
      referenced = conn.select_values(<<~SQL)
        SELECT ccu.table_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
        WHERE tc.table_name = 'audit_logs' AND tc.constraint_type = 'FOREIGN KEY'
      SQL
      expect(referenced).not_to include('projects', 'cells', 'robots', 'tasks')
    end

    it 'a FK para workspaces é ON DELETE RESTRICT (o log impede apagar a linha do workspace)' do
      rule = conn.select_value(<<~SQL)
        SELECT rc.delete_rule
        FROM information_schema.referential_constraints rc
        JOIN information_schema.table_constraints tc ON tc.constraint_name = rc.constraint_name
        WHERE tc.table_name = 'audit_logs' AND rc.constraint_name = 'fk_audit_workspace'
      SQL
      expect(rule).to eq('RESTRICT')
    end
  end
end
