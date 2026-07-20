# frozen_string_literal: true

# workspace-membership §"Person" e §"Conjunto vazio" (tarefa 2.2 / D-6, D-11).
#
# `Person` é a identidade de domínio, DESACOPLADA de `User`: `user_id` é
# deliberadamente nullable para que um técnico de chão de fábrica sem conta possa
# ser responsável por tarefa. O `id` é estável — quando a pessoa depois vira
# usuária, `People::ResolveService` (G5) preenche `user_id` NA LINHA existente e
# o mesmo `person_id` é preservado. Nenhuma coluna de domínio guarda nome como
# chave; toda referência a responsável aponta para `people.id`.
class CreatePeople < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE people (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id uuid NOT NULL REFERENCES workspaces (id),
        name         text  NOT NULL,
        email        citext NULL,
        user_id      uuid  NULL REFERENCES users (id),
        created_at   timestamptz NOT NULL DEFAULT now(),
        updated_at   timestamptz NOT NULL DEFAULT now(),
        -- D11: o sentinela legado "Não Atribuído" é abolido no BANCO. Ausência de
        -- responsável é conjunto vazio de atribuições, nunca uma Person fantasma.
        -- Compara o nome inteiro normalizado (não substring): "Ana Atribuído" passa.
        CONSTRAINT people_name_not_sentinel
          CHECK (btrim(lower(name)) NOT IN ('não atribuído', 'nao atribuido'))
      );

      -- Alvo das FKs compostas de domínio (D-8): (workspace_id, id). Índice
      -- ÚNICO COMPLETO (sem WHERE) — índice parcial não serve de alvo de FK.
      CREATE UNIQUE INDEX index_people_on_workspace_id_and_id
        ON people (workspace_id, id);

      -- Casamento determinístico por e-mail no aceite de convite (case-insensitive
      -- via citext), um por workspace.
      CREATE UNIQUE INDEX index_people_on_workspace_id_and_email
        ON people (workspace_id, email) WHERE email IS NOT NULL;

      -- Um usuário é no máximo uma Person por workspace.
      CREATE UNIQUE INDEX index_people_on_workspace_id_and_user_id
        ON people (workspace_id, user_id) WHERE user_id IS NOT NULL;

      -- Nome único por workspace, normalizado: "João Souza" e " joão souza "
      -- colidem (senão "Minhas Tarefas" §3.6 mostraria metade das tarefas).
      CREATE UNIQUE INDEX index_people_on_workspace_id_and_normalized_name
        ON people (workspace_id, (lower(btrim(name))));
    SQL
  end

  def down
    execute 'DROP TABLE IF EXISTS people'
  end
end
