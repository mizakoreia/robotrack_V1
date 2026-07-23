# frozen_string_literal: true

module Ops
  # Backup verificado (delivery-and-observability 8.3). Um backup que nunca foi
  # RESTAURADO não é um backup — é uma esperança. Esta rotina restaura num banco
  # descartável e compara contagens de tabelas-âncora; o `bin/release` a consulta e
  # ABORTA uma migration `contract` se o backup tem mais de 1h ou não passou no
  # restore. A execução do `pg_dump`/`pg_restore` é injetável (HANDOFF de deploy);
  # a lógica de frescor e comparação é pura e testável.
  module VerifiedBackup
    ANCHOR_TABLES = %w[workspaces projects audit_logs].freeze
    MAX_AGE_SECONDS = 3600 # 1h

    module_function

    # RPO: distância entre o backup e agora.
    def rpo_seconds(backup_time, now)
      (now - backup_time).to_i
    end

    def stale?(backup_time, now, max_age: MAX_AGE_SECONDS)
      backup_time.nil? || rpo_seconds(backup_time, now) > max_age
    end

    # As contagens das tabelas-âncora batem entre origem e restore?
    def counts_match?(source_counts, restored_counts)
      ANCHOR_TABLES.all? { |t| source_counts[t] == restored_counts[t] }
    end

    # Pré-condição para uma migration destrutiva rodar (8.3). Levanta com o motivo;
    # é o que o `bin/release` chama antes de uma migration `contract`.
    def assert_safe_for_contract!(backup:, now: Time.current)
      raise 'backup ausente — migration contract abortada' if backup.nil?

      if stale?(backup[:taken_at], now)
        raise "backup com mais de 1h (RPO #{rpo_seconds(backup[:taken_at], now)}s) — migration contract abortada"
      end

      unless backup[:restore_verified]
        raise 'backup não passou no restore de verificação — migration contract abortada'
      end

      unless counts_match?(backup[:source_counts] || {}, backup[:restored_counts] || {})
        raise 'contagens divergem entre origem e restore — migration contract abortada'
      end

      true
    end
  end
end
