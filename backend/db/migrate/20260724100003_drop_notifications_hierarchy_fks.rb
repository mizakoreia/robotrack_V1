# frozen_string_literal: true

# D-H6 (correção): a versão inicial de `20260724100001_create_notifications`
# criava `ctx_project_id/cell_id/robot_id` como FK `ON DELETE SET NULL` para a
# hierarquia. O contrato (spec/db/hierarchy_fk_contract_spec) exige que
# `notifications` NÃO tenha aresta de FK para projects/cells/robots: o registro de
# que aquele nó existiu tem de sobreviver ao apagamento dele — o id trafega como
# VALOR SOLTO. Esta migração remove as três FKs para os DBs que já aplicaram a
# criação original; em base nova a criação já não as adiciona (IF EXISTS = no-op).
#
# `ctx_task_id` permanece FK de propósito: task é soft-delete (nunca some) e a FK
# ancora o índice único de idempotência de assign.
class DropNotificationsHierarchyFks < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_ctx_project_id_fkey;
      ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_ctx_cell_id_fkey;
      ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_ctx_robot_id_fkey;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE notifications
        ADD CONSTRAINT notifications_ctx_project_id_fkey
        FOREIGN KEY (ctx_project_id) REFERENCES projects(id) ON DELETE SET NULL;
      ALTER TABLE notifications
        ADD CONSTRAINT notifications_ctx_cell_id_fkey
        FOREIGN KEY (ctx_cell_id) REFERENCES cells(id) ON DELETE SET NULL;
      ALTER TABLE notifications
        ADD CONSTRAINT notifications_ctx_robot_id_fkey
        FOREIGN KEY (ctx_robot_id) REFERENCES robots(id) ON DELETE SET NULL;
    SQL
  end
end
