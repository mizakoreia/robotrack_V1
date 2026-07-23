# frozen_string_literal: true

module Ops
  # Expurgo por retenção (delivery-and-observability 6.5). DELETE em LOTES de 5.000
  # para não segurar um lock longo nem inchar o WAL. Agendado diariamente com trava
  # de execução única (o agendador chama `run_all`). Cada alvo é defensivo: uma
  # tabela ainda não criada (a onda dela não veio) é PULADA, não quebra o job.
  #
  #   jwt_denylist   — entradas expiradas (`exp < now`): o logout de D4 continua
  #                    efetivo enquanto o token não expirou; depois disso a linha
  #                    não serve mais.
  #   notifications  — lidas há mais de 90 dias.
  #   login_codes / login_attempts — expirados (magic-link; podem não existir).
  module RetentionPurge
    BATCH = 5_000

    module_function

    def run_all(now: Time.current)
      {
        jwt_denylist: purge_expired('jwt_denylist', "exp < '#{now.utc.iso8601}'"),
        notifications: purge_expired('notifications', "read_at IS NOT NULL AND read_at < '#{(now - 90.days).utc.iso8601}'"),
        login_codes: purge_expired('login_codes', "expires_at < '#{now.utc.iso8601}'"),
        login_attempts: purge_expired('login_attempts', "created_at < '#{(now - 90.days).utc.iso8601}'")
      }
    end

    # Deleta em lotes; devolve o total removido. Pula a tabela se ela não existe.
    def purge_expired(table, where_sql, conn: ActiveRecord::Base.connection)
      return :skipped_missing_table unless conn.data_source_exists?(table)

      total = 0
      loop do
        deleted = conn.exec_delete(<<~SQL.squish, "Purge #{table}")
          DELETE FROM #{table}
          WHERE ctid IN (SELECT ctid FROM #{table} WHERE #{where_sql} LIMIT #{BATCH})
        SQL
        total += deleted
        break if deleted < BATCH
      end
      total
    end
  end
end
