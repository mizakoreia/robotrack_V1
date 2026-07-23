# frozen_string_literal: true

module Ops
  # Manutenção das partições mensais de `audit_logs` (delivery-and-observability
  # 6.2/6.4). A tabela é `PARTITION BY RANGE (ts)`; um insert com `ts` num mês sem
  # partição falharia e derrubaria TODA a escrita de auditoria. Este serviço:
  #   - garante folga de DUAS partições futuras (`ensure_future_partitions`);
  #   - alerta quando a folga cai para uma (`check_and_alert`);
  #   - descarta partições além da retenção (`retention_sweep`) DEPOIS de exportar.
  #
  # A criação/DETACH/DROP são DDL: rodam sob um papel de manutenção (não o
  # robotrack_app, que não tem CREATE). A geração de nome/limites/DDL é pura e
  # testável; a execução é injetável.
  module AuditPartitionMaintenance
    PARENT = 'audit_logs'
    RETENTION_MONTHS = 24

    module_function

    def partition_name(date)
      format('%<parent>s_%<year>04d_%<month>02d', parent: PARENT, year: date.year, month: date.month)
    end

    # Limites [início do mês, início do mês seguinte).
    def partition_bounds(date)
      start = Date.new(date.year, date.month, 1)
      [start, start.next_month]
    end

    def create_ddl(date)
      name = partition_name(date)
      from, to = partition_bounds(date)
      "CREATE TABLE IF NOT EXISTS #{name} PARTITION OF #{PARENT} " \
        "FOR VALUES FROM ('#{from} 00:00:00+00') TO ('#{to} 00:00:00+00');"
    end

    # Meses que DEVEM ter partição: o corrente + N à frente.
    def required_months(now, months_ahead)
      (0..months_ahead).map { |i| now.to_date >> i }
    end

    def existing_partition_names(conn = ActiveRecord::Base.connection)
      conn.select_values(<<~SQL.squish)
        SELECT inhrelid::regclass::text FROM pg_inherits
        WHERE inhparent = '#{PARENT}'::regclass
      SQL
    end

    # Quantas partições cobrem meses >= o corrente (a "folga futura").
    def future_partition_count(now, conn = ActiveRecord::Base.connection)
      current = partition_name(now.to_date)
      existing = existing_partition_names(conn)
      existing.count { |n| n.match?(/\A#{PARENT}_\d{4}_\d{2}\z/) && n >= current }
    end

    def ensure_future_partitions(now: Time.current, months_ahead: 2, conn: ActiveRecord::Base.connection)
      required_months(now, months_ahead).each { |date| conn.execute(create_ddl(date)) }
    end

    def check_and_alert(now: Time.current, conn: ActiveRecord::Base.connection)
      return if future_partition_count(now, conn) >= 2

      Ops::AlertService.raise_alert(
        key: 'audit_partition_low', severity: :warning,
        message: 'Folga de partições futuras de audit_logs caiu abaixo de 2'
      )
    end

    # Partições cujo mês inteiro é mais antigo que a retenção (24 meses).
    def expired_partition_names(now: Time.current, conn: ActiveRecord::Base.connection)
      cutoff = partition_name((now.to_date << RETENTION_MONTHS))
      existing_partition_names(conn).select do |n|
        n.match?(/\A#{PARENT}_\d{4}_\d{2}\z/) && n < cutoff
      end
    end

    # Exporta uma partição para JSON (6.3). O `exporter` é injetável: em produção
    # ele sobe o arquivo para armazenamento de objeto (S3) — HANDOFF de deploy;
    # aqui devolve as linhas em formato lido pelo backup JSON. Roda como robotrack_
    # app (só SELECT, que basta para exportar).
    def export_partition(name, conn: ActiveRecord::Base.connection, exporter: nil)
      rows = conn.select_all("SELECT * FROM #{conn.quote_table_name(name)}").to_a
      dump = { partition: name, exported_at: Time.current.utc.iso8601, rows: rows }
      exporter&.call(dump)
      dump
    end

    # Descarte (6.4): DETACH + DROP, e SÓ depois de a exportação ter sido
    # confirmada. DDL → papel de manutenção. Devolve as SQLs executadas.
    def detach_and_drop(name, conn: ActiveRecord::Base.connection, exported:)
      raise ArgumentError, 'descarte sem exportação confirmada' unless exported

      stmts = [
        "ALTER TABLE #{PARENT} DETACH PARTITION #{conn.quote_table_name(name)};",
        "DROP TABLE #{conn.quote_table_name(name)};"
      ]
      stmts.each { |sql| conn.execute(sql) }
      stmts
    end

    # Varredura completa de retenção (6.4): para cada partição expirada, EXPORTA e
    # só então DETACH+DROP; se a exportação falha, ZERO drop e um alerta warning.
    def retention_sweep(now: Time.current, conn: ActiveRecord::Base.connection, exporter: nil)
      expired_partition_names(now: now, conn: conn).each do |name|
        dump = export_partition(name, conn: conn, exporter: exporter)
        detach_and_drop(name, conn: conn, exported: dump[:rows] || true)
      rescue StandardError => e
        Ops::AlertService.raise_alert(
          key: "audit_partition_drop_failed:#{name}", severity: :warning,
          message: "Descarte de #{name} abortado: #{e.message}"
        )
      end
    end
  end
end
