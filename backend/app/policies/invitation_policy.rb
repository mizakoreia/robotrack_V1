# frozen_string_literal: true

# §4.1 linha 7, inv. 7 (`firestore.rules` L72-77): convite é gestão de membro —
# só o dono cria, lista e revoga. O escopo do convite (workspace do contexto,
# papel só view/edit) é garantido por `Invitations::CreateService` + enum
# `invitation_role` no banco (workspace-invitations D-INV-4).
# Singleton D3.1 — absorve o piso de instância de workspace-invitations.
class InvitationPolicy < BasePolicy
  permits index?: :manage_membership,
          create?: :manage_membership,
          destroy?: :manage_membership
end
