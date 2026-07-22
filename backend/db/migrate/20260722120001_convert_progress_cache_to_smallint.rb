# frozen_string_literal: true

# progress-rollup 1.1 (D5.a/D5.e, EXECUCAO decisão 1) — migration CORRETIVA.
#
# `commissioning-hierarchy` (D-H7) criou `progress_cache` como `jsonb DEFAULT '{}'`
# guardando `{weighted, done, total}`. A spec desta capacidade — a DONA da
# semântica do cache — exige `smallint NOT NULL DEFAULT 0 CHECK (BETWEEN 0 AND 100)`
# guardando SÓ o ponderado (§2.1); a contagem crua NÃO é cacheada (D5.e). O blob
# jsonb é exatamente o número-sem-rótulo que o D15 proíbe, então convertemos.
#
# Sem dado em produção (branch de dev empilhada) — o medo do D-H7 (retrofit com
# backfill e janela nullable) não se aplica. Preserva `progress_cached_at`, agora
# setado pelas escritas de rollup. A `down` reverte para jsonb '{}'.
class ConvertProgressCacheToSmallint < ActiveRecord::Migration[8.0]
  TABLES = %w[projects cells robots].freeze

  def up
    TABLES.each do |t|
      execute(<<~SQL)
        ALTER TABLE #{t} ALTER COLUMN progress_cache DROP DEFAULT;
        ALTER TABLE #{t} ALTER COLUMN progress_cache TYPE smallint
          USING COALESCE((progress_cache ->> 'weighted')::smallint, 0);
        ALTER TABLE #{t} ALTER COLUMN progress_cache SET DEFAULT 0;
        ALTER TABLE #{t} ALTER COLUMN progress_cache SET NOT NULL;
        ALTER TABLE #{t} ADD CONSTRAINT chk_#{t}_progress_cache
          CHECK (progress_cache BETWEEN 0 AND 100);
      SQL
    end
  end

  def down
    TABLES.each do |t|
      execute(<<~SQL)
        ALTER TABLE #{t} DROP CONSTRAINT IF EXISTS chk_#{t}_progress_cache;
        ALTER TABLE #{t} ALTER COLUMN progress_cache DROP DEFAULT;
        ALTER TABLE #{t} ALTER COLUMN progress_cache TYPE jsonb USING '{}'::jsonb;
        ALTER TABLE #{t} ALTER COLUMN progress_cache SET DEFAULT '{}'::jsonb;
      SQL
    end
  end
end
