# frozen_string_literal: true

# workspace-settings G5 (D-RESET-GATE) — consumo do backup como portão anti-replay.
#
# O reset de fábrica exige um `backup_id` recente e `completed`. Sem uma marca de
# consumo, um duplo clique (ou reenvio) dispararia DOIS resets com o mesmo backup. A
# coluna `consumed_at` é carimbada DENTRO da transação do reset; o gate recusa
# (`422`) um backup já consumido. A RLS de `workspace_backups` já concede UPDATE ao
# app (política de UPDATE por `app.current_workspace_id`), então nenhum GRANT novo.
class AddConsumedAtToWorkspaceBackups < ActiveRecord::Migration[8.0]
  def up
    execute('ALTER TABLE workspace_backups ADD COLUMN consumed_at timestamptz NULL;')
  end

  def down
    execute('ALTER TABLE workspace_backups DROP COLUMN consumed_at;')
  end
end
