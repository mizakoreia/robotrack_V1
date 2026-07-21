# frozen_string_literal: true

# workspace-invitations 4.2 / D-INV-7 — snapshot APPEND-ONLY da membership
# removida (decisão de execução 3).
#
# A tarefa pede o snapshot em `audit_logs`, tabela que pertence à change
# `audit-log` e ainda não existe. Criá-la aqui seria invadir o escopo dela e
# gerar conflito depois; ficar sem snapshot deixaria a remoção irreversível. Esta
# tabela é o meio-termo, e serve a DOIS propósitos:
#
#   1. **Backup reversível** (4.2): o dono pode reconstruir manualmente a
#      membership a partir da linha — workspace, pessoa, usuário, papel e o
#      convite que a originou. Por isso é append-only (`REVOKE UPDATE, DELETE`
#      em `db/roles.sql`, com o mesmo argumento de D12): um log que o runtime
#      pode reescrever não é log.
#   2. **`403 workspace_access_revoked`** (5.3): permite distinguir "você foi
#      removido daqui" de "isto não é seu" SEM furar a anti-enumeração — o
#      código diferenciado só aparece para quem comprovadamente TEVE acesso e,
#      portanto, já sabia que o workspace existe. Para todo o resto o servidor
#      continua respondendo o mesmo `403 workspace_access_denied`.
#
# Quando `audit-log` chegar, esta tabela é candidata natural a ser absorvida.
class CreateMembershipRevocations < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE membership_revocations (
        id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id       uuid NOT NULL REFERENCES workspaces (id),
        user_id            uuid NOT NULL REFERENCES users (id),
        person_id          uuid NOT NULL,
        role               membership_role NOT NULL,
        invitation_id      uuid NULL,
        removed_by_user_id uuid NOT NULL REFERENCES users (id),
        created_at         timestamptz NOT NULL DEFAULT now()
      );

      CREATE INDEX index_membership_revocations_on_workspace_and_user
        ON membership_revocations (workspace_id, user_id);

      ALTER TABLE membership_revocations ENABLE ROW LEVEL SECURITY;
      ALTER TABLE membership_revocations FORCE  ROW LEVEL SECURITY;

      -- Mesma forma da política de `memberships`: o tenant corrente OU as
      -- MINHAS próprias linhas. A segunda cláusula é o que permite ao usuário
      -- removido descobrir a revogação quando já não tem workspace nenhum onde
      -- se apoiar.
      CREATE POLICY tenant_isolation ON membership_revocations
        USING (
          workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid
          OR user_id   = NULLIF(current_setting('app.current_user_id', true), '')::uuid
        )
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      -- Append-only para o runtime. Repetido em db/roles.sql porque `pg_dump -x`
      -- OMITE GRANT/REVOKE: um rebuild por `db:schema:load` nasceria sem isto.
      REVOKE UPDATE, DELETE ON membership_revocations FROM robotrack_app;
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS membership_revocations;')
  end
end
