# frozen_string_literal: true

# `class AuditLog` (namespace do model).
class AuditLog
  # audit-log 8.1/8.4 (audit-log-retention) — o job mensal, orquestrando a mecânica:
  # manutenção de partições (cria as futuras, alerta DEFAULT), varredura de ids
  # duplicados, e — para partições elegíveis (> 24 meses) — arquivar+verificar+podar.
  #
  # NÃO é `tenant: true`: é manutenção global (DDL), fora do request. Roda com uma
  # conexão de privilégio de migração/arquivamento; o AGENDAMENTO Sidekiq e as
  # credenciais são de delivery-and-observability (o job não se auto-agenda).
  class RetentionJob < ApplicationJob
    queue_as :default

    # conn: injetada pelo agendador (papel com DDL + leitura de partição). Sem ela,
    # o job não roda — é sinal de configuração de entrega faltando, não silêncio.
    def perform(conn: nil, today: Time.current)
      raise ArgumentError, 'RetentionJob exige conn de privilégio (delivery-and-observability)' if conn.nil?

      PartitionMaintenance.run(conn: conn, today: today)
      ArchiveService.scan_duplicate_ids(conn)

      partitions(conn).select { |p| Retention.eligible?(p, today: today) }.each do |partition|
        ArchiveService.prune(partition: partition, conn: conn)
      rescue ArchiveService::VerificationError, ArgumentError => e
        # falha de verificação/bucket preserva a partição e alerta; segue às demais.
        Rails.logger.error({ event: 'audit_retention_partition_failed', partition: partition, error: e.message }.to_json)
      end
    end

    def partitions(conn)
      conn.exec(<<~SQL).map { |r| r['partition'] }
        SELECT inhrelid::regclass::text AS partition
        FROM pg_inherits WHERE inhparent = 'audit_logs'::regclass
      SQL
    end
  end
end
