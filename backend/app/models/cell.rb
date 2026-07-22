# frozen_string_literal: true

# commissioning-hierarchy §1.1 — célula, escopo de ordem/nome é o PROJETO.
# Cascade e coerência de tenant são FK composta no banco (D-H5/D-H6).
class Cell < ApplicationRecord
  include WorkspaceScoped
  include PositionScoped
  position_scoped_by :project_id

  belongs_to :project
  has_many :robots, dependent: nil
  belongs_to :updated_by_person, class_name: 'Person', optional: true

  # hierarchy-soft-delete D7 — arquivada some da leitura; compõe com o tenant.
  default_scope { where(deleted_at: nil) }
end
