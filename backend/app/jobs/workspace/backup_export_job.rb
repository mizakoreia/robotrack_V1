# frozen_string_literal: true

class Workspace
  # workspace-settings 4.4 (§3.11, D-EXP) — o export ASSÍNCRONO, acima do teto de
  # tarefas síncronas. Roda em contexto de tenant (a RLS exige `app.current_
  # workspace_id`), monta o payload e marca o `WorkspaceBackup` como `completed`
  # (checksum + counts) ou `failed`.
  #
  # DEPENDÊNCIA DE ENTREGA (delivery-and-observability): gravar o arquivo em storage
  # e servir o link de download. Aqui a mecânica; a linha `completed` é a prova de
  # que o backup existe (o gate do reset a exige).
  class BackupExportJob < ApplicationJob
    queue_as :default

    def perform(backup_id, workspace_id)
      ::Tenant.with(workspace_id: workspace_id, user_id: nil) do
        backup = ::WorkspaceBackup.find(backup_id)
        ws = ::Workspace.find(workspace_id)
        export = ::Workspace::BackupExportService.call(workspace: ws)
        # TODO(delivery-and-observability): persistir export[:json] no storage frio.
        backup.update!(status: 'completed', checksum: export[:checksum], counts: export[:counts])
      rescue StandardError => e
        ::WorkspaceBackup.where(id: backup_id).update_all(status: 'failed')
        Rails.logger.error({ event: 'backup_export_failed', backup_id: backup_id, error: e.message }.to_json)
        raise
      end
    end
  end
end
