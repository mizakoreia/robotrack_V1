# frozen_string_literal: true

require 'digest'
require 'json'
require 'zlib'
require 'fileutils'

# `class AuditLog` (namespace do model).
class AuditLog
  # audit-log 8.1–8.6 (audit-log-retention, Decisão 2) — a retenção do log por DDL,
  # NUNCA por DML. A poda é `DETACH PARTITION` + `DROP TABLE` da partição destacada,
  # depois de arquivá-la verificada em storage frio. `DETACH`/`DROP` NÃO disparam a
  # trigger de linha (por isso a poda é DDL: um `DELETE` seria barrado pela
  # imutabilidade — e conceder `DELETE` destruiria a garantia para todo o resto).
  #
  # DEPENDÊNCIA DE ENTREGA (delivery-and-observability): o agendamento Sidekiq, o
  # bucket real de storage frio (`AUDIT_ARCHIVE_BUCKET`), as credenciais (a leitura
  # cross-tenant do arquivamento exige um papel BYPASSRLS dedicado, read-only), as
  # métricas de crescimento e os alertas. Aqui: a MECÂNICA e as garantias (verificado
  # antes de descartar; nunca DELETE; janela de 24 meses só destaca após confirmação).
  module Retention
    module_function

    PREFIX = 'audit_logs_'
    RETENTION_MONTHS = 24 # janela em armazenamento quente (Decisão 2)
    FUTURE_MONTHS = 3     # partições criadas com antecedência (§ manutenção)

    # ---- nomes e faixas de partição (puro) ----

    def partition_name(date) = "#{PREFIX}#{date.strftime('%Y_%m')}"

    # As FUTURE_MONTHS faixas a partir do 1º dia do mês seguinte a `from`.
    def future_partition_specs(from:, months: FUTURE_MONTHS)
      base = from.to_date.beginning_of_month
      (1..months).map do |i|
        start = base.next_month(i)
        { name: partition_name(start), from: start, to: start.next_month }
      end
    end

    # Extrai a data (1º do mês) do nome `audit_logs_AAAA_MM`; nil se não casar.
    def partition_month(name)
      m = name.match(/\A#{PREFIX}(\d{4})_(\d{2})\z/)
      m && Date.new(m[1].to_i, m[2].to_i, 1)
    end

    # Partição elegível à retenção: mais velha que RETENTION_MONTHS.
    def eligible?(name, today:)
      month = partition_month(name)
      return false if month.nil?

      month < today.to_date.beginning_of_month.prev_month(RETENTION_MONTHS)
    end

    # ---- poda por DDL (puro; 8.6) ----

    # As DUAS instruções da poda: destacar e descartar. NUNCA `DELETE FROM
    # audit_logs` (retenção por DML é o modo de falha que a invariante 3 proíbe).
    def detach_and_drop_sql(partition)
      [
        "ALTER TABLE audit_logs DETACH PARTITION #{partition}",
        "DROP TABLE #{partition}"
      ]
    end

    # ---- flags/config ----

    # A janela de 24 meses precisa de confirmação do produto antes do 1º DROP
    # (design Pergunta-em-aberto 3). Enquanto não confirmada, o job arquiva mas NÃO
    # destaca. Default: desligada.
    def confirm_window? = ENV['AUDIT_RETENTION_CONFIRM_WINDOW'] == 'true'

    # Bucket de storage frio — obrigatório (8.2). Ausente → erro explícito nomeando
    # a variável; nada é destacado nem descartado.
    def bucket!
      ENV['AUDIT_ARCHIVE_BUCKET'].presence ||
        raise(ArgumentError, 'AUDIT_ARCHIVE_BUCKET não configurada — arquivamento abortado; ' \
                             'nenhuma partição destacada ou descartada (audit-log 8.2)')
    end

    # ---- checksum (puro) ----

    # Serialização canônica das linhas (ordenadas por id, chaves ordenadas) →
    # sha256. É a mesma base do JSONL exportado, para a verificação bater.
    def checksum(rows) = Digest::SHA256.hexdigest(canonical(rows))

    def canonical(rows)
      rows.sort_by { |r| r['id'] }.map { |r| JSON.generate(r.sort.to_h) }.join("\n")
    end

    # ---- métricas (8.5) ----

    # Contagem de linhas e tamanho em disco POR PARTIÇÃO — a fonte que
    # delivery-and-observability coleta para o alerta de queda de contagem entre
    # coletas (a lógica de janela-de-manutenção e o agendamento são DELES; aqui a
    # medição). A contagem total cross-tenant exige o papel BYPASSRLS de leitura.
    def partition_metrics(conn)
      partitions(conn).map do |p|
        { partition: p,
          rows: conn.exec("SELECT count(*) FROM #{p}").getvalue(0, 0).to_i,
          size_bytes: conn.exec("SELECT pg_total_relation_size('#{p}')").getvalue(0, 0).to_i }
      end
    end

    def partitions(conn)
      conn.exec("SELECT inhrelid::regclass::text AS p FROM pg_inherits WHERE inhparent = 'audit_logs'::regclass")
          .map { |r| r['p'] }
    end
  end
end
