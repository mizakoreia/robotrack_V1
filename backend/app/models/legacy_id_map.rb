# frozen_string_literal: true

# legacy-data-migration 2.1 (D-LDM-2, D-LDM-6) — uma linha do mapa caminho-legado →
# id-novo de um run. NÃO é usado para idempotência (essa mora na PK UUIDv5, D-LDM-2):
# existe para o `rake legacy:rollback[run_id]` apagar EXATAMENTE as linhas do run — e
# só elas — e para diagnóstico/relatório. Único por `(run_id, legacy_path)`.
class LegacyIdMap < ApplicationRecord
  self.table_name = 'legacy_id_map' # singular no schema; o Rails pluralizaria

  include WorkspaceScoped

  belongs_to :run, class_name: 'LegacyImportRun', foreign_key: :run_id, inverse_of: :id_map_entries

  # Vocabulário de `entity_type` (o writer de G4/G5 grava; o rollback lê). A ordem
  # aqui é a de DEPENDÊNCIA (pai → filho); o rollback percorre ao contrário.
  ENTITY_TYPES = %w[
    workspace membership person task_template
    project cell robot task task_assignee task_advance notification audit_log
  ].freeze

  validates :entity_type, presence: true
  validates :legacy_path, presence: true
  validates :new_id, presence: true
end
