# frozen_string_literal: true

# my-tasks-view 2.2 (D-MTV-5) — índice PARCIAL de tarefas abertas por workspace.
# `done`/`N/A` dominam um workspace maduro (estado terminal de quase tudo) e esta
# tela NUNCA os lê; um índice não-parcial infla com exatamente as linhas ignoradas.
#
# Os literais são os do ENUM REAL `task_status` (pt-BR) — NÃO os placeholders
# `pending`/`in_progress` do design.md. Se `robot-tasks` adicionar um 5º status, o
# spec do enum (2.3) falha antes deste índice divergir em silêncio.
#
# Idempotente (`IF NOT EXISTS`): `hierarchy-screens`/`progress-rollup` podem tê-lo
# criado. CONCURRENTLY → `disable_ddl_transaction!`.
class AddOpenTasksPartialIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute(<<~SQL)
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tasks_open_ws
        ON tasks (workspace_id, id)
        WHERE status IN ('Pendente', 'Em Andamento');
    SQL
  end

  def down
    execute('DROP INDEX CONCURRENTLY IF EXISTS idx_tasks_open_ws;')
  end
end
