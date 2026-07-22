# frozen_string_literal: true

# workspace-settings G1 (§3.11) — o registro de um backup emitido (a prova de que
# houve backup; pré-requisito do reset). `WorkspaceScoped` auto-atribui workspace_id
# do contexto e o default_scope o filtra (RLS é a garantia).
class WorkspaceBackup < ApplicationRecord
  include WorkspaceScoped

  STATUSES = %w[pending completed failed].freeze

  validates :status, inclusion: { in: STATUSES }
end
