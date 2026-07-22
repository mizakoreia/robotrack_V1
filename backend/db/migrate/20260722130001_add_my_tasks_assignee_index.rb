# frozen_string_literal: true

# my-tasks-view 2.1 (D-MTV-5) — o índice que sustenta o PONTO DE ENTRADA de
# "Minhas Tarefas": dado `(workspace_id, person_id)`, as tarefas da pessoa.
# `INCLUDE (task_id)` mantém a etapa de driver como index-only scan (sem visitar a
# heap de `task_assignees`) — sem ele o p95 estoura no dataset de carga.
#
# CONCURRENTLY (sem lock de escrita) exige `disable_ddl_transaction!`. `IF NOT
# EXISTS` torna a migration idempotente.
class AddMyTasksAssigneeIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute(<<~SQL)
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_task_assignees_ws_person
        ON task_assignees (workspace_id, person_id) INCLUDE (task_id);
    SQL
  end

  def down
    execute('DROP INDEX CONCURRENTLY IF EXISTS idx_task_assignees_ws_person;')
  end
end
