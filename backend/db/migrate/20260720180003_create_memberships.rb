# frozen_string_literal: true

# workspace-membership §"Papéis" e §"Membership" (tarefa 2.3 / D-5, D-8).
#
# O enum Postgres `membership_role` tem EXATAMENTE `edit` e `view`. `owner` NÃO é
# valor de enum — é derivado de `workspaces.owner_user_id` (§4.1 inv. 5). Assim
# `UPDATE memberships SET role='owner'` falha com "invalid input value for enum",
# não com validação de model. A FK composta (workspace_id, person_id) garante que
# a Person vinculada pertence ao MESMO workspace — apontar para fora é rejeitado
# pelo banco, não apenas tornado invisível pela RLS (D-8).
class CreateMemberships < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TYPE membership_role AS ENUM ('edit', 'view');

      CREATE TABLE memberships (
        id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id  uuid NOT NULL REFERENCES workspaces (id),
        user_id       uuid NOT NULL REFERENCES users (id),
        person_id     uuid NOT NULL,
        role          membership_role NOT NULL,
        invitation_id uuid NULL,
        created_at    timestamptz NOT NULL DEFAULT now(),
        updated_at    timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT fk_memberships_person_same_workspace
          FOREIGN KEY (workspace_id, person_id)
          REFERENCES people (workspace_id, id)
      );

      -- Papel único por (workspace, usuário): a segunda membership do mesmo
      -- usuário no mesmo workspace viola o índice.
      CREATE UNIQUE INDEX index_memberships_on_workspace_id_and_user_id
        ON memberships (workspace_id, user_id);

      -- Índice do alvo da FK composta e de consultas por pessoa.
      CREATE INDEX index_memberships_on_workspace_id_and_person_id
        ON memberships (workspace_id, person_id);
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TABLE IF EXISTS memberships;
      DROP TYPE IF EXISTS membership_role;
    SQL
  end
end
