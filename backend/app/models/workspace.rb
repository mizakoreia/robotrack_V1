# frozen_string_literal: true

# workspace-core §"Entidade Workspace".
#
# O dono é `owner_user_id` (não uma membership) e é imutável no banco
# (§4.1 inv. 5, migration ProtectWorkspaceOwner). `responsibles` não é coluna —
# é a projeção de `people` (D11).
class Workspace < ApplicationRecord
  belongs_to :owner, class_name: 'User', foreign_key: 'owner_user_id', inverse_of: :owned_workspace

  has_many :people, dependent: :restrict_with_exception
  has_many :memberships, dependent: :restrict_with_exception

  validates :name, presence: true
end
