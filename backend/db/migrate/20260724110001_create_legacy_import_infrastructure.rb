# frozen_string_literal: true

# legacy-data-migration 2.1 (D-LDM-2, D-LDM-6) — a infraestrutura de RUN da importação
# legada: o registro de cada execução (`legacy_import_runs`) e o mapa
# caminho-legado → id-novo (`legacy_id_map`) que torna o rollback CIRÚRGICO (por run),
# em vez de `pg_restore` do banco inteiro.
#
# Por que `legacy_id_map`: a idempotência mora na PK (UUIDv5 do caminho, D-LDM-2) — o
# mapa NÃO é usado para deduplicar. Ele existe para (a) o `rake legacy:rollback[run_id]`
# saber EXATAMENTE quais linhas aquele run criou e apagar só elas (D-LDM-6), (b) o
# diagnóstico e o relatório de validação. `file_sha256` no run é o que detecta a
# reimportação de um arquivo diferente para um workspace já importado (8.4).
#
# TENANCY: ambas são tabelas de DOMÍNIO — o `schema_guard` exige `workspace_id NOT NULL`
# + índice liderado por `workspace_id` + FORCE RLS + policy `tenant_isolation`. Por isso
# `legacy_id_map` carrega `workspace_id` DENORMALIZADO do run (a spec da 2.1 lista só
# `run_id`; sem `workspace_id` a tabela reprovaria a guarda e o rollback não teria como
# escopar por RLS). Rodam como `robotrack_app` sob RLS, com `app.current_workspace_id`
# setado — o mesmo contexto que o importador e o rollback abrem.
#
# `legacy_import_runs` aceita UPDATE (status `pending`→`completed`/`failed`/`rolled_back`
# e `report`), como `workspace_backups`; `legacy_id_map` é append-only na prática
# (SELECT/INSERT) — o mapa é a PROVA do que o run criou e não é reescrito.
class CreateLegacyImportInfrastructure < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE legacy_import_runs (
        id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id     uuid NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
        legacy_owner_uid text NOT NULL,
        file_sha256      text NOT NULL,
        backup_path      text,
        status           text NOT NULL DEFAULT 'pending',
        report           jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at       timestamptz NOT NULL DEFAULT now(),
        updated_at       timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT chk_lir_status
          CHECK (status IN ('pending', 'completed', 'failed', 'rolled_back'))
      );

      CREATE INDEX index_legacy_import_runs_on_workspace_created
        ON legacy_import_runs (workspace_id, created_at DESC);

      -- Busca da 8.4: "este workspace já foi importado, e com que hash?".
      CREATE INDEX index_legacy_import_runs_on_workspace_sha
        ON legacy_import_runs (workspace_id, file_sha256);

      ALTER TABLE legacy_import_runs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE legacy_import_runs FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON legacy_import_runs FOR SELECT
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
      CREATE POLICY tenant_isolation_insert ON legacy_import_runs FOR INSERT
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
      CREATE POLICY tenant_isolation_update ON legacy_import_runs FOR UPDATE
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      CREATE TABLE legacy_id_map (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        run_id       uuid NOT NULL REFERENCES legacy_import_runs (id) ON DELETE CASCADE,
        workspace_id uuid NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
        entity_type  text NOT NULL,
        legacy_path  text NOT NULL,
        new_id       uuid NOT NULL,
        created_at   timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_legacy_id_map_run_path UNIQUE (run_id, legacy_path)
      );

      -- Índice liderado por workspace_id (schema_guard) e que serve o rollback:
      -- "todas as linhas deste run, por tipo de entidade, em ordem de dependência".
      CREATE INDEX index_legacy_id_map_on_ws_run_entity
        ON legacy_id_map (workspace_id, run_id, entity_type);

      ALTER TABLE legacy_id_map ENABLE ROW LEVEL SECURITY;
      ALTER TABLE legacy_id_map FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON legacy_id_map FOR SELECT
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
      CREATE POLICY tenant_isolation_insert ON legacy_id_map FOR INSERT
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TABLE IF EXISTS legacy_id_map;
      DROP TABLE IF EXISTS legacy_import_runs;
    SQL
  end
end
