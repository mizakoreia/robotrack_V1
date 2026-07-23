# frozen_string_literal: true

# realtime-collaboration 3.1 / D6.5 — a sequência monotônica por workspace que
# sustenta a detecção de lacuna na reconexão. Aditiva, reversível, sem backfill e
# sem destrutivo: `default 0` já é o "nunca publicou nada".
#
# O GRANT de coluna é a outra metade: `db/roles.sql` revoga o UPDATE de tabela de
# `workspaces` do `robotrack_app` e devolve só `(name, updated_at)`; sem incluir
# `realtime_seq`, o `UPDATE ... RETURNING` do publisher levaria
# `permission denied for column realtime_seq`. Concedemos aqui (banco existente) e
# replicamos em `roles.sql` (rebuild) — `pg_dump -x` do structure.sql OMITE
# GRANT/REVOKE, mesmo caveat do audit-log e do dono imutável.
class AddRealtimeSeqToWorkspaces < ActiveRecord::Migration[8.0]
  def up
    add_column :workspaces, :realtime_seq, :bigint, null: false, default: 0

    execute(<<~SQL)
      GRANT UPDATE (realtime_seq) ON workspaces TO robotrack_app;
    SQL
  end

  def down
    execute(<<~SQL)
      REVOKE UPDATE (realtime_seq) ON workspaces FROM robotrack_app;
    SQL

    remove_column :workspaces, :realtime_seq
  end
end
