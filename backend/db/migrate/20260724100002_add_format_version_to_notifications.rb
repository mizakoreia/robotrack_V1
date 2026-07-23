# frozen_string_literal: true

# in-app-notifications 2.2 (§2.7 linha 165) — `format_version` registra qual bloco
# de mensagens (v1, v2, …) renderizou a `msg`. Faltou no create original; entra
# aqui com DEFAULT 1. Também entra na comparação do trigger de inv. 4 (não pode
# mudar num UPDATE de leitura).
class AddFormatVersionToNotifications < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      ALTER TABLE notifications ADD COLUMN format_version smallint NOT NULL DEFAULT 1;

      CREATE OR REPLACE FUNCTION notifications_only_read_update() RETURNS trigger AS $$
      BEGIN
        IF OLD.read IS TRUE AND NEW.read IS FALSE THEN
          RAISE EXCEPTION 'notifications: não é permitido desmarcar como lida (inv. 4)';
        END IF;
        IF ROW(NEW.id, NEW.workspace_id, NEW.recipient_person_id, NEW.actor_person_id,
               NEW.type, NEW.msg, NEW.author_name_snapshot, NEW.recorded_at, NEW.created_at,
               NEW.ts_local, NEW.format_version, NEW.ctx_project_id, NEW.ctx_cell_id,
               NEW.ctx_robot_id, NEW.ctx_task_id)
           IS DISTINCT FROM
           ROW(OLD.id, OLD.workspace_id, OLD.recipient_person_id, OLD.actor_person_id,
               OLD.type, OLD.msg, OLD.author_name_snapshot, OLD.recorded_at, OLD.created_at,
               OLD.ts_local, OLD.format_version, OLD.ctx_project_id, OLD.ctx_cell_id,
               OLD.ctx_robot_id, OLD.ctx_task_id)
        THEN
          RAISE EXCEPTION 'notifications: só read/read_at podem mudar (inv. 4)';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE notifications DROP COLUMN format_version;
    SQL
  end
end
