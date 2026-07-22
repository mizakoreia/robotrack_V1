# frozen_string_literal: true

# workspace-settings G1 (§3.11, D1/D2, D-RESET-GATE) — o registro de um backup
# emitido. É a PROVA auditável de que houve backup, e o pré-requisito do reset de
# fábrica (`backup_id` ≤ 15 min, `status = completed`). `counts` guarda as
# contagens exportadas; `checksum` o sha256 do payload (D-EXP). RLS como as demais
# tabelas de domínio (o `schema_guard` exige workspace_id NOT NULL + índice
# liderado por workspace_id + FORCE RLS + policy `tenant_isolation`).
#
# UPDATE é permitido (o job assíncrono muda `pending` → `completed`/`failed`) — por
# isso há policy de UPDATE, ao contrário de `audit_logs`. NÃO é apagado pelo reset
# (é a prova do backup); sem policy de DELETE.
class CreateWorkspaceBackups < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE workspace_backups (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id uuid NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
        status       text NOT NULL DEFAULT 'pending',
        checksum     text,
        counts       jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at   timestamptz NOT NULL DEFAULT now(),
        updated_at   timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT chk_wb_status CHECK (status IN ('pending', 'completed', 'failed'))
      );

      CREATE INDEX index_workspace_backups_on_workspace_created
        ON workspace_backups (workspace_id, created_at DESC);

      ALTER TABLE workspace_backups ENABLE ROW LEVEL SECURITY;
      ALTER TABLE workspace_backups FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON workspace_backups FOR SELECT
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
      CREATE POLICY tenant_isolation_insert ON workspace_backups FOR INSERT
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
      CREATE POLICY tenant_isolation_update ON workspace_backups FOR UPDATE
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS workspace_backups;')
  end
end
