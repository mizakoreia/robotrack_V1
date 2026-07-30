# frozen_string_literal: true

# notification-preferences G1 (D-P1/D-P2/D2). Preferência de notificação POR
# ENTIDADE da hierarquia, por pessoa: cada linha diz que uma `person_id` quer
# `follow` (receber mesmo sem ser responsável) ou `mute` (silenciar) um alvo —
# projeto, célula OU robô (exatamente um, CHECK `num_nonnulls = 1`).
#
# Alvo por TRÊS colunas FK (não polimórfico textual): mesmo motivo do `ctx` de
# `notifications` ser 4 colunas e não jsonb (D-N2) — integridade referencial de
# graça. `ON DELETE CASCADE` a partir de cada pai: apagar o robô apaga as
# preferências dele; nada pendurado.
#
# FKs COMPOSTAS com `workspace_id` nas duas pontas (padrão de `task_assignees`):
# é impossível no banco uma preferência de WS-A apontar para um alvo de WS-B.
# Ordem das colunas casa os índices únicos existentes: `people(workspace_id, id)`
# e `projects/cells/robots(id, workspace_id)`.
#
# RLS FORÇADA no idioma exato das demais tabelas de tenant (D2). GRANT ao
# `robotrack_app` é automático (default-privileges do `robotrack_migrator`,
# `db/roles.sql`) — tabela mutável, sem REVOKE de imutabilidade.
#
# Reversão: `DROP TABLE`/`DROP TYPE` — barata (a parte NÃO-trivial, `ALTER TYPE
# notification_type ADD VALUE 'structure'`, é o G6 DEFERIDO, fora desta migração).
class CreateNotificationSubscriptions < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TYPE notification_subscription_state AS ENUM ('follow', 'mute');

      CREATE TABLE notification_subscriptions (
        id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id      uuid NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
        person_id         uuid NOT NULL,
        scope_project_id  uuid,
        scope_cell_id     uuid,
        scope_robot_id    uuid,
        state             notification_subscription_state NOT NULL,
        created_at        timestamptz NOT NULL DEFAULT now(),
        updated_at        timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_notif_sub_one_scope
          CHECK (num_nonnulls(scope_project_id, scope_cell_id, scope_robot_id) = 1),

        CONSTRAINT fk_notif_sub_person
          FOREIGN KEY (workspace_id, person_id)
          REFERENCES people (workspace_id, id) ON DELETE CASCADE,
        CONSTRAINT fk_notif_sub_project
          FOREIGN KEY (scope_project_id, workspace_id)
          REFERENCES projects (id, workspace_id) ON DELETE CASCADE,
        CONSTRAINT fk_notif_sub_cell
          FOREIGN KEY (scope_cell_id, workspace_id)
          REFERENCES cells (id, workspace_id) ON DELETE CASCADE,
        CONSTRAINT fk_notif_sub_robot
          FOREIGN KEY (scope_robot_id, workspace_id)
          REFERENCES robots (id, workspace_id) ON DELETE CASCADE
      );

      -- Índice liderado por workspace_id: guarda de tenancy + custo de RLS.
      CREATE INDEX index_notification_subscriptions_on_workspace_id
        ON notification_subscriptions (workspace_id);

      -- Uma preferência por pessoa por alvo (idempotência do upsert de G3).
      CREATE UNIQUE INDEX uq_notif_sub_person_project
        ON notification_subscriptions (person_id, scope_project_id) WHERE scope_project_id IS NOT NULL;
      CREATE UNIQUE INDEX uq_notif_sub_person_cell
        ON notification_subscriptions (person_id, scope_cell_id)    WHERE scope_cell_id    IS NOT NULL;
      CREATE UNIQUE INDEX uq_notif_sub_person_robot
        ON notification_subscriptions (person_id, scope_robot_id)   WHERE scope_robot_id   IS NOT NULL;

      -- Lookup do resolver (G2): dado um galho, as linhas relevantes por nível.
      CREATE INDEX idx_notif_sub_by_project ON notification_subscriptions (scope_project_id) WHERE scope_project_id IS NOT NULL;
      CREATE INDEX idx_notif_sub_by_cell    ON notification_subscriptions (scope_cell_id)    WHERE scope_cell_id    IS NOT NULL;
      CREATE INDEX idx_notif_sub_by_robot   ON notification_subscriptions (scope_robot_id)   WHERE scope_robot_id   IS NOT NULL;

      ALTER TABLE notification_subscriptions ENABLE ROW LEVEL SECURITY;
      ALTER TABLE notification_subscriptions FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON notification_subscriptions
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS notification_subscriptions;')
    execute('DROP TYPE IF EXISTS notification_subscription_state;')
  end
end
