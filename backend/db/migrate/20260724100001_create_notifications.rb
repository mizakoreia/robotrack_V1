# frozen_string_literal: true

# in-app-notifications 1.1-1.5 (D-N2). Roda como robotrack_migrator. As invariantes
# 4 e 8 vivem no BANCO (CHECK + triggers), não no ActiveRecord — o spec de 1.6 as
# exercita por SQL cru.
class CreateNotifications < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE TYPE notification_type AS ENUM ('assign', 'progress', 'done');

      CREATE TABLE notifications (
        id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id          uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        recipient_person_id   uuid NOT NULL REFERENCES people(id) ON DELETE CASCADE,
        actor_person_id       uuid NOT NULL REFERENCES people(id) ON DELETE CASCADE,
        type                  notification_type NOT NULL,
        msg                   text NOT NULL,
        author_name_snapshot  text NOT NULL,
        recorded_at           timestamptz NOT NULL,
        created_at            timestamptz NOT NULL DEFAULT now(),
        ts_local              text NOT NULL,
        read                  boolean NOT NULL DEFAULT false,
        read_at               timestamptz NULL,
        -- D-H6: os ids da hierarquia vão como VALOR SOLTO, não como referência —
        -- a notificação de que o robô/célula/projeto existiu tem de SOBREVIVER ao
        -- apagamento dele (nada de FK/cascade da hierarquia; ver hierarchy_fk_
        -- contract_spec). `ctx_task_id` mantém FK: task é soft-delete (nunca some)
        -- e a FK ancora o índice único de idempotência de assign.
        ctx_project_id        uuid NULL,
        ctx_cell_id           uuid NULL,
        ctx_robot_id          uuid NULL,
        ctx_task_id           uuid NULL REFERENCES tasks(id) ON DELETE SET NULL,

        CONSTRAINT msg_max_500 CHECK (char_length(msg) <= 500),
        CONSTRAINT read_at_coherence CHECK (
          (read = false AND read_at IS NULL) OR (read = true AND read_at IS NOT NULL)
        )
      );

      -- RLS: mesmo idioma de D2. SET app.current_workspace_id de A não vê B.
      ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
      ALTER TABLE notifications FORCE  ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON notifications
        USING      (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      -- Invariante 8: read=true no INSERT FALHA (não "corrige" para false).
      CREATE FUNCTION notifications_no_insert_read() RETURNS trigger AS $$
      BEGIN
        IF NEW.read IS TRUE THEN
          RAISE EXCEPTION 'notifications: read deve ser false no INSERT (inv. 8)';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER notifications_before_insert
        BEFORE INSERT ON notifications
        FOR EACH ROW EXECUTE FUNCTION notifications_no_insert_read();

      -- Invariante 4: UPDATE só pode tocar {read, read_at}; read:true→false proibido.
      CREATE FUNCTION notifications_only_read_update() RETURNS trigger AS $$
      BEGIN
        IF OLD.read IS TRUE AND NEW.read IS FALSE THEN
          RAISE EXCEPTION 'notifications: não é permitido desmarcar como lida (inv. 4)';
        END IF;
        IF ROW(NEW.id, NEW.workspace_id, NEW.recipient_person_id, NEW.actor_person_id,
               NEW.type, NEW.msg, NEW.author_name_snapshot, NEW.recorded_at, NEW.created_at,
               NEW.ts_local, NEW.ctx_project_id, NEW.ctx_cell_id, NEW.ctx_robot_id, NEW.ctx_task_id)
           IS DISTINCT FROM
           ROW(OLD.id, OLD.workspace_id, OLD.recipient_person_id, OLD.actor_person_id,
               OLD.type, OLD.msg, OLD.author_name_snapshot, OLD.recorded_at, OLD.created_at,
               OLD.ts_local, OLD.ctx_project_id, OLD.ctx_cell_id, OLD.ctx_robot_id, OLD.ctx_task_id)
        THEN
          RAISE EXCEPTION 'notifications: só read/read_at podem mudar (inv. 4)';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER notifications_before_update
        BEFORE UPDATE ON notifications
        FOR EACH ROW EXECUTE FUNCTION notifications_only_read_update();

      -- Idempotência de assign (§2.7): reenfileirar a mesma atribuição não duplica.
      CREATE UNIQUE INDEX idx_notifications_assign_idempotency
        ON notifications (recipient_person_id, ctx_task_id, type, recorded_at)
        WHERE type = 'assign';

      -- Leitura do centro (D-N10): escopo por destinatário, ordem recorded_at DESC.
      CREATE INDEX idx_notifications_center
        ON notifications (workspace_id, recipient_person_id, recorded_at DESC);

      -- Retenção (D-N10): read + recorded_at para o expurgo de 90 dias.
      CREATE INDEX idx_notifications_retention
        ON notifications (workspace_id, read, recorded_at);
    SQL
  end

  def down
    execute <<~SQL
      DROP TABLE IF EXISTS notifications;
      DROP FUNCTION IF EXISTS notifications_no_insert_read();
      DROP FUNCTION IF EXISTS notifications_only_read_update();
      DROP TYPE IF EXISTS notification_type;
    SQL
  end
end
