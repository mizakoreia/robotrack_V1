# frozen_string_literal: true

# progress-advances G1 (D-IMUT / Q1, EXECUCAO decisão 1) — soft-delete em `tasks`.
#
# A trilha `task_advances` é IMUTÁVEL (trigger recusa DELETE), então uma tarefa
# com avanços NÃO pode ser apagada em cascata. Contrato fechado com robot-tasks:
# `tasks` usa soft-delete (`deleted_at`) e a FK de `task_advances → tasks` é
# `ON DELETE RESTRICT`. O `DeleteService` de robot-tasks passa a setar `deleted_at`.
#
# O índice de dedup `(robot_id, lower(btrim(desc)))` vira PARCIAL
# (`WHERE deleted_at IS NULL`): uma tarefa soft-deleted não ocupa mais a `desc`,
# então recriar/sincronizar a mesma `desc` naquele robô volta a funcionar.
class AddSoftDeleteToTasks < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE tasks ADD COLUMN deleted_at timestamptz NULL;

      DROP INDEX index_tasks_on_robot_lower_desc;
      CREATE UNIQUE INDEX index_tasks_on_robot_lower_desc
        ON tasks (robot_id, lower(btrim("desc"))) WHERE deleted_at IS NULL;

      CREATE INDEX index_tasks_on_deleted_at ON tasks (deleted_at) WHERE deleted_at IS NOT NULL;
    SQL
  end

  def down
    execute(<<~SQL)
      DROP INDEX IF EXISTS index_tasks_on_deleted_at;
      DROP INDEX index_tasks_on_robot_lower_desc;
      CREATE UNIQUE INDEX index_tasks_on_robot_lower_desc
        ON tasks (robot_id, lower(btrim("desc")));
      ALTER TABLE tasks DROP COLUMN deleted_at;
    SQL
  end
end
