# frozen_string_literal: true

require 'digest'
require 'json'
require 'zlib'
require 'stringio'
require 'fileutils'

# `class AuditLog` (namespace do model).
class AuditLog
  # audit-log 8.2–8.4 (audit-log-retention, Decisão 2) — arquivamento VERIFICADO
  # antes de qualquer descarte. Exporta a partição para JSONL comprimido em storage
  # frio + manifesto (contagem + checksum), VERIFICA o arquivo contra a partição, e
  # só então — se a janela de 24 meses estiver confirmada — destaca e descarta por
  # DDL. Falha de verificação, bucket ausente ou janela não confirmada → NADA é
  # destacado; as linhas continuam consultáveis.
  #
  # conn: conexão do papel com privilégio de DDL (destacar/descartar) e leitura da
  # partição. A leitura CROSS-TENANT do arquivamento exige um papel BYPASSRLS
  # read-only (delivery-and-observability); aqui a mecânica.
  module ArchiveService
    module_function

    COLUMNS = %w[id workspace_id event_type format_version msg ts ts_local by_person_id by_name payload].freeze

    # Exporta a partição: JSONL.gz + manifesto. Retorna o manifesto.
    def export(partition:, conn:)
      bucket = Retention.bucket!
      FileUtils.mkdir_p(bucket)
      rows = read_partition(conn, partition)

      write_gz(File.join(bucket, "#{partition}.jsonl.gz"), rows)
      manifest = { 'partition' => partition, 'row_count' => rows.size, 'checksum' => Retention.checksum(rows) }
      File.write(File.join(bucket, "#{partition}.manifest.json"), JSON.pretty_generate(manifest))
      manifest
    end

    # Verifica o ARQUIVO contra a PARTIÇÃO (contagem + checksum). Diverge → aborta
    # (raise), sem destacar (8.3). O arquivo é a fonte lida; a partição é reconferida.
    def verify(partition:, conn:)
      bucket = Retention.bucket!
      file_rows = read_gz(File.join(bucket, "#{partition}.jsonl.gz"))
      part_rows = read_partition(conn, partition)

      if file_rows.size != part_rows.size
        raise VerificationError,
              "verificação falhou em #{partition}: arquivo tem #{file_rows.size} linha(s), " \
              "partição tem #{part_rows.size} — abortado, nada destacado (audit-log 8.3)"
      end
      if Retention.checksum(file_rows) != Retention.checksum(part_rows)
        raise VerificationError, "verificação falhou em #{partition}: checksum diverge — abortado, nada destacado"
      end
      true
    end

    # Arquiva → verifica → (se a janela confirmada) destaca+descarta. Ordem
    # inviolável: DROP só após verify passar E a flag ligada.
    def prune(partition:, conn:)
      export(partition: partition, conn: conn)
      verify(partition: partition, conn: conn)

      unless Retention.confirm_window?
        Rails.logger.info({ event: 'audit_partition_archived_not_detached', partition: partition,
                            reason: 'janela de 24 meses não confirmada (AUDIT_RETENTION_CONFIRM_WINDOW)' }.to_json)
        return { partition: partition, archived: true, detached: false }
      end

      Retention.detach_and_drop_sql(partition).each { |sql| conn.exec(sql) }
      Rails.logger.info({ event: 'audit_partition_pruned', partition: partition }.to_json)
      { partition: partition, archived: true, detached: true }
    end

    # Varre `audit_logs` por id duplicado entre partições (a PK é (ts, id); a
    # unicidade de `id` repousa no uuid v4, Decisão 2). Alerta, NÃO remove.
    def scan_duplicate_ids(conn)
      dups = conn.exec('SELECT id FROM audit_logs GROUP BY id HAVING count(*) > 1').map { |r| r['id'] }
      dups.each do |id|
        Rails.logger.warn({ event: 'audit_duplicate_id', id: id,
                            message: "id de auditoria duplicado em partições distintas: #{id}" }.to_json)
      end
      dups
    end

    # ---- io ----

    def read_partition(conn, partition)
      conn.exec("SELECT #{COLUMNS.join(', ')} FROM #{partition} ORDER BY id").map { |r| r }
    end

    def write_gz(path, rows)
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      rows.each { |r| gz.puts(JSON.generate(r.sort.to_h)) }
      gz.close
      File.binwrite(path, io.string)
    end

    def read_gz(path)
      raise ArgumentError, "arquivo de arquivamento ausente: #{path}" unless File.exist?(path)

      Zlib::GzipReader.open(path) { |gz| gz.each_line.map { |l| JSON.parse(l) } }
    end

    class VerificationError < StandardError; end
  end
end
