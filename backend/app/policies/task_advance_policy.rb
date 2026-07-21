# frozen_string_literal: true

# progress-advances 4.1 (§4.1, D3) — registrar avanço é `record_progress`
# (owner/edit; `view` recebe 403). Ler a trilha é `read_workspace` (qualquer
# membro, inclusive `view`). Nenhuma comparação de papel aqui: a decisão sai
# inteira da PermissionMatrix, como toda policy do template.
class TaskAdvancePolicy < BasePolicy
  permits create?: :record_progress,
          index?: :read_workspace
end
