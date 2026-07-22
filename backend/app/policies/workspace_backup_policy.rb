# frozen_string_literal: true

# workspace-settings 1.3 (§4.1, D-EXP-ROLE) — export de backup é `owner`-only, apesar
# de `view` poder LER o workspace: o arquivo carrega e-mails de membros/convites
# (dado que a UI nunca expõe a não-donos) e sai do alcance de qualquer revogação
# futura — é exfiltração autorizada. `edit`/`view` recebem 403.
class WorkspaceBackupPolicy < BasePolicy
  permits create?: :destroy_workspace,
          show?: :destroy_workspace
end
