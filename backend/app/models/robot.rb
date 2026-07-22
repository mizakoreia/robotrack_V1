# frozen_string_literal: true

# commissioning-hierarchy §1.1/§1.2 — robô, escopo de ordem/nome é a CÉLULA.
# `application` é validada pelo CHECK do banco (D-H10); a lista aqui é
# conveniência de leitura para a UI/catálogo (§1.3).
class Robot < ApplicationRecord
  include WorkspaceScoped
  include PositionScoped
  position_scoped_by :cell_id

  APPLICATIONS = ['Misto / Geral', 'Solda Ponto', 'Solda MIG', 'Handling', 'Sealing', 'Outros'].freeze

  belongs_to :cell
  belongs_to :updated_by_person, class_name: 'Person', optional: true

  # hierarchy-soft-delete D7 — arquivado some da leitura; compõe com o tenant.
  default_scope { where(deleted_at: nil) }
end
