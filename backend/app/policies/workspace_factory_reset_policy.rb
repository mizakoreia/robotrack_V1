# frozen_string_literal: true

# workspace-settings 1.3 (§4.1, D12) — o reset de fábrica é EXCLUSIVO do dono
# (`destroy_workspace`). `edit` com a frase de confirmação e um `backup_id` corretos
# AINDA recebe 403 — a matriz separa "editar catálogo/equipe" (owner/edit) de
# "destruir/reset" (owner). Sem outra action.
class WorkspaceFactoryResetPolicy < BasePolicy
  permits create?: :destroy_workspace
end
