# frozen_string_literal: true

# workspace-invitations 4.2 — snapshot append-only da membership removida.
#
# Sem `update`/`destroy` no runtime: o privilégio foi revogado no banco
# (`db/roles.sql`), então uma tentativa de reescrever o log falha lá, não aqui. O
# `readonly?` do model é apenas a mensagem de erro amigável antes disso.
class MembershipRevocation < ApplicationRecord
  include WorkspaceScoped

  belongs_to :user
  belongs_to :person, optional: true
  belongs_to :removed_by, class_name: 'User', foreign_key: 'removed_by_user_id', inverse_of: false

  def readonly?
    persisted?
  end
end
