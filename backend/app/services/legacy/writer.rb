# frozen_string_literal: true

module Legacy
  # legacy-data-migration 4.2 (D-LDM-2) — o wrapper de escrita idempotente. Toda linha
  # importada entra por aqui: `INSERT … ON CONFLICT (id) DO NOTHING` (via `insert_all`, que
  # PULA conflitos), contando CRIADOS vs. PULADOS, e grava em paralelo o `legacy_id_map`
  # dos que foram criados. NUNCA `DO UPDATE`: o 2º run não pode sobrescrever edição feita
  # no sistema novo depois do corte — "zero registros novos" E "zero dano" (D-LDM-2).
  #
  # `id` vem SEMPRE de `Legacy::IdDerivation` (uuidv5 do caminho legado); é a PK que carrega
  # a idempotência. O writer exige contexto de tenant (fail-closed via ImportContext) e
  # espera que cada `attrs` já traga `workspace_id` (o WITH CHECK da RLS o valida).
  module Writer
    Result = Struct.new(:created, :skipped, keyword_init: true) do
      def merge(other)
        Result.new(created: created + other.created, skipped: skipped + other.skipped)
      end
    end

    module_function

    # model:       o AR model destino (Robot, Project, …).
    # entity_type: rótulo do legacy_id_map (LegacyIdMap::ENTITY_TYPES).
    # run:         o LegacyImportRun (para run_id/workspace_id do mapa).
    # entries:     array de { id:, legacy_path:, attrs: } — attrs SEM :id (é injetado),
    #              COM :workspace_id e as colunas NOT NULL sem default.
    def insert(model:, entity_type:, run:, entries:)
      ImportContext.require_context!
      return Result.new(created: 0, skipped: 0) if entries.blank?

      rows = entries.map { |e| e[:attrs].merge(id: e[:id]) }
      # unique_by: :id força `ON CONFLICT (id) DO NOTHING` (o contrato de D-LDM-2). Sem ele,
      # o `insert_all` tentaria inferir árbitros e esbarraria na unique DEFERÍVEL de posição.
      inserted = model.insert_all(rows, unique_by: :id, returning: %w[id])
      created_ids = inserted.rows.flatten.to_set

      record_map(run, entity_type, entries, created_ids)
      Result.new(created: created_ids.size, skipped: entries.size - created_ids.size)
    end

    # Grava o mapa APENAS dos criados (o 2º run cria 0 → 0 linhas novas de mapa). Também
    # `ON CONFLICT DO NOTHING` no único `(run_id, legacy_path)`, por segurança.
    def record_map(run, entity_type, entries, created_ids)
      map_rows = entries.select { |e| created_ids.include?(e[:id]) }.map do |e|
        { run_id: run.id, workspace_id: run.workspace_id,
          entity_type: entity_type, legacy_path: e[:legacy_path], new_id: e[:id] }
      end
      LegacyIdMap.insert_all(map_rows) if map_rows.any?
    end
  end
end
