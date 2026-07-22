# frozen_string_literal: true

# `class AuditLog` (namespace do model).
class AuditLog
  # audit-log 8.1 (audit-log-retention) — a manutenção mensal das partições: cria as
  # dos FUTURE_MONTHS meses seguintes (com a RLS por partição, via
  # `secure_audit_partition`) e ALERTA se a partição `DEFAULT` recebeu linhas — SEM
  # removê-las (a `DEFAULT` é rede: um registro nela é sinal de partição do mês
  # faltando, não lixo). Roda como o papel de migração (DDL), fora do request.
  module PartitionMaintenance
    module_function

    # conn: uma conexão PG do papel DONO (migrator) — CREATE/ATTACH são DDL.
    # today: injeta a data (o job passa a corrente; specs congelam).
    def run(conn:, today: Time.current)
      created = ensure_future_partitions(conn, today)
      default_rows = default_partition_row_count(conn)
      alert_default_partition(default_rows) if default_rows.positive?

      { created: created, default_row_count: default_rows }
    end

    def ensure_future_partitions(conn, today)
      Retention.future_partition_specs(from: today).filter_map do |spec|
        next if partition_exists?(conn, spec[:name])

        conn.exec(<<~SQL)
          CREATE TABLE #{spec[:name]} PARTITION OF audit_logs
            FOR VALUES FROM ('#{spec[:from]}') TO ('#{spec[:to]}')
        SQL
        conn.exec("SELECT secure_audit_partition('#{spec[:name]}'::regclass)")
        spec[:name]
      end
    end

    def partition_exists?(conn, name)
      conn.exec_params('SELECT to_regclass($1) IS NOT NULL', ["public.#{name}"]).getvalue(0, 0) == 't'
    end

    def default_partition_row_count(conn)
      conn.exec('SELECT count(*) FROM audit_logs_default').getvalue(0, 0).to_i
    end

    def alert_default_partition(count)
      # O alerta real (canal) é de delivery-and-observability; aqui o sinal
      # estruturado nomeando a contagem, e o retorno para o job propagar.
      Rails.logger.warn(
        { event: 'audit_default_partition_nonempty', rows: count,
          message: "partição DEFAULT com #{count} linha(s) — mês corrente sem partição dedicada" }.to_json
      )
    end
  end
end
