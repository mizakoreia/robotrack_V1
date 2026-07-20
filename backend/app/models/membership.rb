# frozen_string_literal: true

# workspace-membership §"Membership" e §"Papéis".
#
# `role` é o enum Postgres `membership_role` (edit|view). `owner` NÃO é papel de
# membership — é derivado de `workspaces.owner_user_id` e resolvido no servidor
# (D-5). O dono nunca vira linha aqui (trigger memberships_owner_is_not_member).
class Membership < ApplicationRecord
  belongs_to :workspace
  belongs_to :user
  belongs_to :person

  enum :role, { edit: 'edit', view: 'view' }

  validates :role, presence: true
end
