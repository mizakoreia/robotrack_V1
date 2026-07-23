# frozen_string_literal: true

require 'rails_helper'
require 'pg'
require 'tmpdir'
require 'zlib'
require 'json'

# audit-log 8.1–8.6 (audit-log-retention, Decisão 2) — a MECÂNICA da retenção por
# DDL. Parte pura (sem banco, sempre roda): faixas de partição futuras, elegibilidade,
# o SQL de poda (DETACH+DROP, NUNCA DELETE — 8.6), bucket obrigatório, checksum. Parte
# de banco (conexão do DONO — DDL): manutenção de partições, export→verify→prune, com
# limpeza `ensure` (a truncation do DatabaseCleaner NÃO reverte DDL).
RSpec.describe 'audit-log — retenção por DDL', :tenancy, type: :request do
  describe 'puro (8.1/8.4/8.6, Decisão 2)' do
    it 'cria faixas dos 3 meses seguintes (2026-03-14 → abril/maio/junho)' do
      names = AuditLog::Retention.future_partition_specs(from: Date.new(2026, 3, 14)).map { |s| s[:name] }
      expect(names).to eq(%w[audit_logs_2026_04 audit_logs_2026_05 audit_logs_2026_06])
    end

    it 'elegibilidade: partição mais velha que 24 meses é elegível; recente não' do
      today = Date.new(2026, 7, 15)
      expect(AuditLog::Retention.eligible?('audit_logs_2024_01', today: today)).to be(true)
      expect(AuditLog::Retention.eligible?('audit_logs_2025_08', today: today)).to be(false)
      expect(AuditLog::Retention.eligible?('audit_logs_default', today: today)).to be(false)
    end

    it '8.6 — a poda é DETACH PARTITION + DROP TABLE, e NUNCA DELETE FROM audit_logs' do
      sql = AuditLog::Retention.detach_and_drop_sql('audit_logs_2024_01')
      joined = sql.join(' ; ')
      expect(joined).to match(/ALTER TABLE audit_logs DETACH PARTITION audit_logs_2024_01/)
      expect(joined).to match(/DROP TABLE audit_logs_2024_01/)
      expect(joined).not_to match(/DELETE\s+FROM\s+audit_logs/i)
    end

    it '8.2 — AUDIT_ARCHIVE_BUCKET ausente aborta nomeando a variável' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AUDIT_ARCHIVE_BUCKET').and_return(nil)
      expect { AuditLog::Retention.bucket! }.to raise_error(ArgumentError, /AUDIT_ARCHIVE_BUCKET/)
    end

    it 'checksum é determinístico e independe da ordem de entrada' do
      a = [{ 'id' => '2', 'msg' => 'b' }, { 'id' => '1', 'msg' => 'a' }]
      b = [{ 'id' => '1', 'msg' => 'a' }, { 'id' => '2', 'msg' => 'b' }]
      expect(AuditLog::Retention.checksum(a)).to eq(AuditLog::Retention.checksum(b))
    end
  end

  describe 'banco — manutenção e arquivamento (conexão do DONO)' do
    let(:owner) { create(:user, name: 'Ana Dona') }
    let(:ws)    { make_workspace(owner: owner) }

    def mig
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      c = PG.connect(host: cfg[:host] || 'localhost', dbname: cfg[:database],
                     user: ENV.fetch('MIGRATOR_DB_USER', 'robotrack_migrator'),
                     password: ENV.fetch('MIGRATOR_DB_PASSWORD', 'mig_dev_pw'))
      c.exec("SELECT set_config('app.current_workspace_id', '#{ws.id}', false)")
      c
    end

    def create_partition(conn, name, from, to)
      conn.exec("CREATE TABLE #{name} PARTITION OF audit_logs FOR VALUES FROM ('#{from}') TO ('#{to}')")
      conn.exec("SELECT secure_audit_partition('#{name}'::regclass)")
    end

    def seed_rows(conn, n, ts)
      n.times do |i|
        conn.exec(
          "INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name) " \
          "VALUES (gen_random_uuid(), '#{ws.id}', 'task_completed', 1, 'linha #{i}', '#{ts}', 'x', 'Ana')"
        )
      end
    end

    # `today` da manutenção para o teste 8.1. A migração cria o LASTRO de partições
    # [mês corrente .. +3] usando o relógio REAL de quando roda; escolher meses
    # ESTRITAMENTE anteriores ao mês corrente garante disjunção com esse lastro,
    # seja qual for o relógio da máquina (aqui e a migração usam o MESMO
    # `Time.current`). -5 meses → a manutenção cria now-4/-3/-2, disjunto do lastro
    # e dentro da retenção (< 24 meses). Fixar '2026-03-14' era frágil: quando o
    # relógio real caía em abril–junho, 04/05/06 já existiam no lastro e colidiam.
    def maintenance_today
      Time.current.utc.beginning_of_month.advance(months: -5)
    end

    def maintenance_future_names
      base = maintenance_today.beginning_of_month
      (1..3).map { |i| "audit_logs_#{base.advance(months: i).strftime('%Y_%m')}" }
    end

    around do |example|
      @bucket = Dir.mktmpdir('audit-archive')
      ENV['AUDIT_ARCHIVE_BUCKET'] = @bucket
      @conn = mig
      example.run
    ensure
      (['audit_logs_2024_01'] + maintenance_future_names).each do |p|
        @conn.exec("DROP TABLE IF EXISTS #{p}")
      rescue StandardError
        nil
      end
      @conn&.close
      ENV.delete('AUDIT_ARCHIVE_BUCKET')
      FileUtils.remove_entry(@bucket) if @bucket && File.exist?(@bucket)
    end

    it '8.1 — manutenção cria as partições futuras e alerta se a DEFAULT tem linhas' do
      ws # força a criação do workspace antes de usar a conn do migrator
      # uma linha vai para a DEFAULT (mês sem partição dedicada — 2027)
      seed_rows(@conn, 1, '2027-05-10 12:00:00+00')
      result = AuditLog::PartitionMaintenance.run(conn: @conn, today: maintenance_today)
      expect(result[:created]).to include(*maintenance_future_names)
      expect(result[:default_row_count]).to be >= 1
      # a linha da DEFAULT NÃO é removida
      remaining = @conn.exec('SELECT count(*) FROM audit_logs_default').getvalue(0, 0).to_i
      expect(remaining).to be >= 1
    end

    it '8.3 — export gera arquivo+manifesto; verify passa; arquivo adulterado aborta e preserva a partição' do
      ws
      create_partition(@conn, 'audit_logs_2024_01', '2024-01-01', '2024-02-01')
      seed_rows(@conn, 5, '2024-01-15 12:00:00+00')

      manifest = AuditLog::ArchiveService.export(partition: 'audit_logs_2024_01', conn: @conn)
      expect(manifest['row_count']).to eq(5)
      expect(File.exist?(File.join(@bucket, 'audit_logs_2024_01.jsonl.gz'))).to be(true)
      expect(AuditLog::ArchiveService.verify(partition: 'audit_logs_2024_01', conn: @conn)).to be(true)

      # adultera o arquivo (remove 1 linha) → verify aborta, partição intacta
      path = File.join(@bucket, 'audit_logs_2024_01.jsonl.gz')
      lines = Zlib::GzipReader.open(path) { |gz| gz.readlines }
      io = StringIO.new; gz = Zlib::GzipWriter.new(io); gz.write(lines[0..-2].join); gz.close
      File.binwrite(path, io.string)

      expect { AuditLog::ArchiveService.verify(partition: 'audit_logs_2024_01', conn: @conn) }
        .to raise_error(AuditLog::ArchiveService::VerificationError, /arquivo tem 4.*partição tem 5|checksum/)
      expect(@conn.exec("SELECT to_regclass('audit_logs_2024_01') IS NOT NULL").getvalue(0, 0)).to eq('t')
      expect(@conn.exec('SELECT count(*) FROM audit_logs_2024_01').getvalue(0, 0).to_i).to eq(5)
    end

    it '8.4 — janela NÃO confirmada: arquiva e verifica, mas NÃO destaca' do
      ws
      create_partition(@conn, 'audit_logs_2024_01', '2024-01-01', '2024-02-01')
      seed_rows(@conn, 3, '2024-01-10 12:00:00+00')
      allow(AuditLog::Retention).to receive(:confirm_window?).and_return(false)

      result = AuditLog::ArchiveService.prune(partition: 'audit_logs_2024_01', conn: @conn)
      expect(result).to include(archived: true, detached: false)
      # a partição continua anexada e consultável
      expect(@conn.exec("SELECT to_regclass('audit_logs_2024_01') IS NOT NULL").getvalue(0, 0)).to eq('t')
    end

    it '8.4 — janela confirmada: destaca e descarta por DDL (partição some), após verify' do
      ws
      create_partition(@conn, 'audit_logs_2024_01', '2024-01-01', '2024-02-01')
      seed_rows(@conn, 3, '2024-01-10 12:00:00+00')
      allow(AuditLog::Retention).to receive(:confirm_window?).and_return(true)

      result = AuditLog::ArchiveService.prune(partition: 'audit_logs_2024_01', conn: @conn)
      expect(result).to include(archived: true, detached: true)
      expect(@conn.exec("SELECT to_regclass('audit_logs_2024_01')").getvalue(0, 0)).to be_nil
    end

    it 'RetentionJob orquestra: mantém partições, varre dups e arquiva a elegível (flag off → não destaca)' do
      ws
      create_partition(@conn, 'audit_logs_2024_01', '2024-01-01', '2024-02-01')
      seed_rows(@conn, 4, '2024-01-20 12:00:00+00')
      allow(AuditLog::Retention).to receive(:confirm_window?).and_return(false)

      AuditLog::RetentionJob.new.perform(conn: @conn, today: Time.utc(2026, 7, 15))

      # a elegível (2024_01) foi ARQUIVADA (arquivo existe) mas NÃO destacada
      expect(File.exist?(File.join(@bucket, 'audit_logs_2024_01.jsonl.gz'))).to be(true)
      expect(@conn.exec("SELECT to_regclass('audit_logs_2024_01') IS NOT NULL").getvalue(0, 0)).to eq('t')
      # a corrente (2026_07) NÃO é elegível → nenhum arquivo dela
      expect(File.exist?(File.join(@bucket, 'audit_logs_2026_07.jsonl.gz'))).to be(false)
    end

    it 'RetentionJob sem conn falha explícito (config de entrega faltando, não silêncio)' do
      expect { AuditLog::RetentionJob.new.perform }.to raise_error(ArgumentError, /conn de privilégio/)
    end

    it '8.5 — expõe métricas de contagem e tamanho por partição (fonte p/ o alerta de queda)' do
      ws
      create_partition(@conn, 'audit_logs_2024_01', '2024-01-01', '2024-02-01')
      seed_rows(@conn, 6, '2024-01-05 12:00:00+00')
      metrics = AuditLog::Retention.partition_metrics(@conn)
      alvo = metrics.find { |m| m[:partition] == 'audit_logs_2024_01' }
      expect(alvo[:rows]).to eq(6)
      expect(alvo[:size_bytes]).to be > 0
      # inclui as partições correntes também (a superfície inteira)
      expect(metrics.map { |m| m[:partition] }).to include('audit_logs_default')
    end
  end
end
