# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 6.1/6.2/6.5/6.6 — ciclo de vida de `audit_logs` e expurgo.
RSpec.describe 'Retenção e ciclo de vida de dado' do
  let(:conn) { ActiveRecord::Base.connection }

  describe 'conformidade da partição de audit_logs (6.1)' do
    it 'é particionada por RANGE em ts' do
      partkey = conn.select_value("SELECT pg_get_partkeydef('audit_logs'::regclass)")
      expect(partkey).to eq('RANGE (ts)')
    end

    it 'as partições seguem a convenção mensal audit_logs_YYYY_MM' do
      names = Ops::AuditPartitionMaintenance.existing_partition_names(conn)
      monthly = names.grep(/\Aaudit_logs_\d{4}_\d{2}\z/)
      expect(monthly).not_to be_empty
    end
  end

  describe 'manutenção de partição (6.2)' do
    it 'gera nome, limites e DDL mensais corretos' do
      d = Date.new(2026, 7, 15)
      expect(Ops::AuditPartitionMaintenance.partition_name(d)).to eq('audit_logs_2026_07')
      expect(Ops::AuditPartitionMaintenance.partition_bounds(d)).to eq([Date.new(2026, 7, 1), Date.new(2026, 8, 1)])
      expect(Ops::AuditPartitionMaintenance.create_ddl(d)).to include(
        "PARTITION OF audit_logs FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00')"
      )
    end

    it 'required_months traz o corrente + N à frente' do
      months = Ops::AuditPartitionMaintenance.required_months(Time.utc(2026, 7, 15), 2)
      expect(months.map { |m| [m.year, m.month] }).to eq([[2026, 7], [2026, 8], [2026, 9]])
    end

    it 'expired_partition_names marca só o que é mais antigo que 24 meses' do
      expired = Ops::AuditPartitionMaintenance.expired_partition_names(now: Time.utc(2029, 8, 1), conn: conn)
      # As partições atuais (2026_07..2026_10) ficam > 24 meses antes de 2029-08.
      expect(expired).to include('audit_logs_2026_07')
    end
  end

  describe 'permissão de retenção — audit_logs write-protected (6.6)' do
    it 'o papel de runtime NÃO pode DELETE em audit_logs' do
      expect do
        conn.transaction(requires_new: true) { conn.execute('DELETE FROM audit_logs') }
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied|InsufficientPrivilege/)
    end

    it 'o papel de runtime NÃO pode UPDATE em audit_logs' do
      expect do
        conn.transaction(requires_new: true) { conn.execute('UPDATE audit_logs SET msg = msg') }
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied|InsufficientPrivilege/)
    end
  end

  describe 'expurgo em lote (6.5)' do
    before do
      conn.execute("INSERT INTO jwt_denylist (jti, exp, created_at, updated_at) VALUES " \
                   "('expirado', now() - interval '1 day', now(), now()), " \
                   "('vivo', now() + interval '2 days', now(), now())")
    end

    it 'remove só as entradas expiradas do jwt_denylist' do
      removed = Ops::RetentionPurge.purge_expired('jwt_denylist', "exp < '#{Time.current.utc.iso8601}'", conn: conn)
      expect(removed).to eq(1)
      restantes = conn.select_values('SELECT jti FROM jwt_denylist')
      expect(restantes).to contain_exactly('vivo')
    end

    it 'pula tabelas ainda inexistentes sem quebrar' do
      result = Ops::RetentionPurge.run_all
      # notifications existe (in-app-notifications, Onda D-N) → poda de fato (0 aqui);
      # login_codes/login_attempts (magic-link) não existem → pulados.
      expect(result[:notifications]).to be_a(Integer)
      expect(result[:login_codes]).to eq(:skipped_missing_table)
    end
  end
end
