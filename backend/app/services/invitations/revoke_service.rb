# frozen_string_literal: true

module Invitations
  # workspace-invitations §"Revogação de convite pendente" (tarefa 2.4 /
  # `firestore.rules` L81, que também deletava).
  #
  # Revogar é `DELETE` real. Um convite JÁ CONSUMIDO não é revogável: apagá-lo
  # destruiria a prova auditável de por que aquela pessoa tem acesso (e o
  # `ON DELETE RESTRICT` da membership impediria de qualquer forma). A orientação
  # nesse caso é remover o membro.
  #
  # Convite de OUTRO workspace não é "negado", é INVISÍVEL: a RLS não devolve a
  # linha e o resultado é `404`. Responder `403` ali vazaria a existência de WS-B.
  class RevokeService
    include ApiResponseHandler

    def initialize(current_user:, current_role:, workspace_id:, invitation_id:)
      @current_user = current_user
      @current_role = current_role
      @workspace_id = workspace_id
      @invitation_id = invitation_id
    end

    def call
      policy = InvitationPolicy.new(role: @current_role, user: @current_user, workspace_id: @workspace_id)
      return error_response('forbidden', 403) unless policy.destroy?

      invitation = find_invitation
      return error_response('invitation_not_found', 404) if invitation.nil?
      return error_response('invitation_already_used', 422) if invitation.used?

      invitation.destroy!
      success_response({}, 204)
    end

    private

    def find_invitation
      Invitation.find_by(id: @invitation_id)
    rescue ActiveRecord::StatementInvalid
      # id malformado (não-uuid) é indistinguível de inexistente.
      nil
    end
  end
end
