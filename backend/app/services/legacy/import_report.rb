# frozen_string_literal: true

module Legacy
  # legacy-data-migration 5-8 (D-LDM-5, D-LDM-7) — o relatório acumulado de um run: criados/
  # pulados por entidade, a lista de QUARENTENA (registro que não entrou: legacy_path + campo
  # + valor bruto + motivo, D-LDM-7) e os AVISOS (divergências que não impedem o import, ex.
  # app_filters_divergentes, homônimo por acento, msg truncada). Persistido em
  # `legacy_import_runs.report` (jsonb).
  class ImportReport
    attr_reader :created, :skipped, :quarantine, :warnings

    def initialize
      @created = Hash.new(0)
      @skipped = Hash.new(0)
      @quarantine = []
      @warnings = []
    end

    def add_write(entity_type, result)
      @created[entity_type] += result.created
      @skipped[entity_type] += result.skipped
    end

    def quarantine!(legacy_path:, field:, value:, reason:)
      @quarantine << { 'legacy_path' => legacy_path, 'field' => field,
                       'value' => value, 'reason' => reason }
    end

    def warn!(legacy_path:, reason:, **extra)
      @warnings << { 'legacy_path' => legacy_path, 'reason' => reason }.merge(extra.transform_keys(&:to_s))
    end

    def quarantine_reason?(reason) = @quarantine.any? { |q| q['reason'] == reason }
    def warning_reason?(reason) = @warnings.any? { |w| w['reason'] == reason }

    def to_h
      {
        'created' => @created.transform_keys(&:to_s),
        'skipped' => @skipped.transform_keys(&:to_s),
        'quarantine' => @quarantine,
        'warnings' => @warnings
      }
    end
  end
end
