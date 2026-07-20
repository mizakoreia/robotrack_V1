# frozen_string_literal: true

# workspace-core §"Entidade Workspace" (tarefa 2.1).
#
# id uuid gerável pelo cliente (D1 — o bootstrap sob RLS precisa fornecer o id
# para satisfazer o WITH CHECK da própria linha que cria). owner_user_id NOT NULL
# com índice único: um usuário é dono de no máximo um workspace (§1.1). SEM
# coluna `responsibles` — a lista de responsáveis é a projeção de `people` (D11).
class CreateWorkspaces < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE workspaces (
        id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        name          text NOT NULL,
        owner_user_id uuid NOT NULL REFERENCES users (id),
        created_at    timestamptz NOT NULL DEFAULT now(),
        updated_at    timestamptz NOT NULL DEFAULT now()
      );

      CREATE UNIQUE INDEX index_workspaces_on_owner_user_id
        ON workspaces (owner_user_id);
    SQL
  end

  def down
    execute 'DROP TABLE IF EXISTS workspaces'
  end
end
