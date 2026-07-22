# frozen_string_literal: true

module Api
  module V1
    # workspace-settings 4.3/4.4 (§3.11, D-EXP/D-EXP-ROLE) — `POST /api/v1/workspace/
    # backups`. `owner`-only (o arquivo carrega e-mails; `edit`/`view` → 403 pelo
    # gate). Persiste a linha em `workspace_backups` (a prova exigida pelo reset).
    #
    # Síncrono até MAX_SYNC_TASKS tarefas: responde o `RoboTrack_Database.json`
    # (Content-Disposition) com o id do backup no header `X-Backup-Id` — o cliente
    # baixa o arquivo E captura o id para o reset. Acima do teto: enfileira o job e
    # responde `202` com o `backup_id` e `status` (o download vem por link depois —
    # o storage real é de delivery-and-observability).
    class WorkspaceBackups < Grape::API
      helpers Api::V1::ControllerHelpers

      MAX_SYNC_TASKS = ENV.fetch('BACKUP_MAX_SYNC_TASKS', '5000').to_i
      FILENAME = 'RoboTrack_Database.json'

      resource :workspace do
        resource :backups do
          route_setting :policy, policy: 'WorkspaceBackupPolicy', action: :create
          post do
            ws = ::Workspace.find(env['api.current_workspace_id'])
            backup = ::WorkspaceBackup.create!(status: 'pending')

            if ::Task.where(deleted_at: nil).count > MAX_SYNC_TASKS
              ::Workspace::BackupExportJob.perform_later(backup.id, ws.id)
              status 202
              content_type 'application/json'
              env['api.format'] = :binary
              body JSON.generate(backup_id: backup.id, status: 'pending')
            else
              export = ::Workspace::BackupExportService.call(workspace: ws)
              backup.update!(status: 'completed', checksum: export[:checksum], counts: export[:counts])

              status 200
              content_type 'application/json'
              header['Content-Disposition'] = %(attachment; filename="#{FILENAME}")
              header['X-Backup-Id'] = backup.id
              env['api.format'] = :binary
              body export[:json]
            end
          end
        end
      end
    end
  end
end
