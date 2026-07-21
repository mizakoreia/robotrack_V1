# frozen_string_literal: true

# workspace-membership §"Membership" e §"Papéis".
#
# `role` é o enum Postgres `membership_role` (edit|view). `owner` NÃO é papel de
# membership — é derivado de `workspaces.owner_user_id` e resolvido no servidor
# (D-5). O dono nunca vira linha aqui (trigger memberships_owner_is_not_member).
class Membership < ApplicationRecord
  include WorkspaceScoped

  belongs_to :user
  belongs_to :person

  # workspace-invitations 1.3: a membership nascida de um convite guarda a
  # referência (ON DELETE RESTRICT no banco) — é a prova auditável de por que
  # aquela pessoa tem acesso. `optional` porque memberships migradas do legado e
  # as criadas por outros caminhos nascem sem convite.
  belongs_to :invitation, optional: true

  enum :role, { edit: 'edit', view: 'view' }

  validates :role, presence: true
end
