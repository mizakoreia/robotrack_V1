# frozen_string_literal: true

# robot-tasks 2.1–2.3 (§1.1, D-RT-1, D10/D11, D2).
#
# Responsável é `person_id`, NUNCA nome (D10/D11): o legado guardava lista de
# nomes + `resp` + o sentinela "Não Atribuído", e renomear uma pessoa órfãnava
# suas atribuições. Aqui a atribuição é uma linha `(task_id, person_id)`;
# ausência de responsável é ZERO linhas, não uma pessoa "Não Atribuído".
#
# FKs COMPOSTAS com o `workspace_id` nas duas pontas (D-RT-1): é impossível no
# banco atribuir pessoa de WS-B a tarefa de WS-A — a FK exige o MESMO
# `workspace_id`. `ON DELETE CASCADE` a partir de `tasks` (a atribuição morre com
# a tarefa); `ON DELETE RESTRICT` a partir de `people` (remover pessoa com
# atribuição é decisão de workspace-tenancy, não apagamento silencioso aqui).
#
# A ordem das colunas nas FKs casa os índices únicos existentes:
# `tasks(id, workspace_id)` e `people(workspace_id, id)` (mesmo padrão de
# `memberships`).
class CreateTaskAssignees < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE task_assignees (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id uuid NOT NULL REFERENCES workspaces (id),
        task_id      uuid NOT NULL,
        person_id    uuid NOT NULL,
        created_at   timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT uq_task_assignees_task_person UNIQUE (task_id, person_id),
        CONSTRAINT fk_task_assignees_task_same_workspace
          FOREIGN KEY (task_id, workspace_id)
          REFERENCES tasks (id, workspace_id) ON DELETE CASCADE,
        CONSTRAINT fk_task_assignees_person_same_workspace
          FOREIGN KEY (workspace_id, person_id)
          REFERENCES people (workspace_id, id) ON DELETE RESTRICT
      );

      -- Índice liderado por workspace_id: guarda de tenancy + custo de RLS.
      CREATE INDEX index_task_assignees_on_workspace_id ON task_assignees (workspace_id);

      -- "Minhas Tarefas" (§3.6): dado um person_id, as tarefas dele.
      CREATE INDEX index_task_assignees_on_person_task ON task_assignees (person_id, task_id);
      -- (task_id, person_id) já é coberto pelo índice do UNIQUE acima.

      ALTER TABLE task_assignees ENABLE ROW LEVEL SECURITY;
      ALTER TABLE task_assignees FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON task_assignees
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS task_assignees;')
  end
end
