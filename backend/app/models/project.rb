# frozen_string_literal: true

# commissioning-hierarchy §1.1 — raiz da hierarquia de comissionamento.
#
# `dependent: nil` de propósito: o cascade de exclusão é FK do BANCO (D-H6) —
# excluir projeto com 200 robôs é UM DELETE, não 200 callbacks. As invariantes
# (nome único por workspace, position única, tenancy) moram em constraint/RLS;
# o model é ergonomia.
class Project < ApplicationRecord
  include WorkspaceScoped
  include PositionScoped
  position_scoped_by :workspace_id

  has_many :cells, dependent: nil
  belongs_to :updated_by_person, class_name: 'Person', optional: true
end
