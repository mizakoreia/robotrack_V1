# frozen_string_literal: true

# workspace-membership §"Membership" e §"Papéis".
#
# `role` é o enum Postgres `membership_role` (edit|view). `owner` NÃO é papel de
# membership — é derivado de `workspaces.owner_user_id` e resolvido no servidor
# (D-5). O dono nunca vira linha aqui (trigger memberships_owner_is_not_member).
class Membership < ApplicationRecord
  include WorkspaceScoped
  include RealtimePublishable

  belongs_to :user
  belongs_to :person

  # realtime-collaboration 3.3 / D6.3 — o vocabulário da membership não é o verbo
  # genérico: uma atualização é `role_changed`, uma exclusão é `revoked` (é o que
  # o eventMap e a revogação viva do G8 consomem). Escopo é o workspace inteiro
  # (invalida `members`/`people`), sem cadeia de rollup.
  def realtime_event_type(action)
    { created: 'membership.created', updated: 'membership.role_changed', destroyed: 'membership.revoked' }.fetch(action)
  end

  # realtime-collaboration 8.1 / D6.7 — o envelope leva o `user_id` afetado (é
  # identidade/ponteiro, não conteúdo): é como o cliente sabe se a revogação é
  # DELE (sai do workspace) ou de outro membro (só invalida members/people).
  def realtime_entity
    { kind: 'membership', id: id, user_id: user_id }
  end

  # workspace-invitations 1.3: a membership nascida de um convite guarda a
  # referência (ON DELETE RESTRICT no banco) — é a prova auditável de por que
  # aquela pessoa tem acesso. `optional` porque memberships migradas do legado e
  # as criadas por outros caminhos nascem sem convite.
  belongs_to :invitation, optional: true

  enum :role, { edit: 'edit', view: 'view' }

  validates :role, presence: true
end
