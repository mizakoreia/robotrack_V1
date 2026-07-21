# frozen_string_literal: true

module Memberships
  # team-access-management §"Remoção de membro" (tarefas 4.2, 4.3, 5.4).
  #
  # Três garantias, nesta ordem, dentro de UMA transação:
  #
  # 1. **Snapshot antes** (4.2): a linha de `membership_revocations` é gravada
  #    ANTES da remoção. Se algo falhar depois, o rollback leva as duas — nunca
  #    fica um log sem remoção nem uma remoção sem log.
  # 2. **A `Person` sobrevive** (4.3): o removido pode ter 12 tarefas atribuídas;
  #    apagar a `Person` as deixaria órfãs. O que se limpa é o `user_id` — ela
  #    volta a ser um responsável sem conta, exatamente o que era antes do
  #    convite.
  # 3. **O convite consumido sobrevive**: `memberships.invitation_id` referencia
  #    o convite com `ON DELETE RESTRICT` e ele é a prova de por que aquela
  #    pessoa teve acesso. Remover o membro não reabre o convite (ele continua
  #    `used_at` preenchido) — para readmitir, cria-se outro.
  #
  # O dono NÃO é removível: um workspace sem dono é irrecuperável (invariante 5).
  class RemoveService
    include ApiResponseHandler

    def initialize(current_user:, current_role:, workspace_id:, membership_id:)
      @current_user = current_user
      @current_role = current_role
      @workspace_id = workspace_id
      @membership_id = membership_id
    end

    def call
      policy = MembershipPolicy.new(role: @current_role, user: @current_user, workspace_id: @workspace_id)
      return error_response('forbidden', 403) unless policy.destroy?

      membership = find_membership
      if membership.nil?
        return error_response('cannot_remove_owner', 422) if owner_row?

        return error_response('membership_not_found', 404)
      end

      remove!(membership)
      publish_revocation(membership)
      success_response({}, 204)
    end

    private

    def find_membership
      Membership.find_by(id: @membership_id)
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def owner_row?
      owner_user_id = Workspace.where(id: @workspace_id).pick(:owner_user_id)
      return false if owner_user_id.nil?

      @membership_id.to_s == owner_user_id.to_s ||
        Person.where(id: @membership_id, user_id: owner_user_id).exists?
    rescue ActiveRecord::StatementInvalid
      false
    end

    def remove!(membership)
      ActiveRecord::Base.transaction(requires_new: true) do
        MembershipRevocation.create!(
          workspace_id: membership.workspace_id,
          user_id: membership.user_id,
          person_id: membership.person_id,
          role: membership.role,
          invitation_id: membership.invitation_id,
          removed_by_user_id: @current_user.id
        )

        person = Person.find_by(id: membership.person_id)
        membership.destroy!
        person&.update!(user_id: nil)
      end
    end

    # D-INV-7, caminho EMPURRADO. `realtime-collaboration` (Onda 8) é quem
    # entrega o `WorkspaceChannel`; até lá isto é um no-op deliberado — a
    # detecção continua funcionando pelo fallback de `403
    # workspace_access_revoked`, que não depende de Cable nenhum. A notificação
    # do ActiveSupport é emitida sempre: é o gancho por onde `audit-log` e
    # `delivery-and-observability` vão pendurar o que precisarem.
    def publish_revocation(membership)
      payload = {
        type: 'membership_revoked',
        workspace_id: membership.workspace_id,
        person_id: membership.person_id,
        user_id: membership.user_id
      }
      ActiveSupport::Notifications.instrument('membership.revoked', payload)

      return unless defined?(::WorkspaceChannel) && ::WorkspaceChannel.respond_to?(:broadcast_to_workspace)

      ::WorkspaceChannel.broadcast_to_workspace(membership.workspace_id, payload)
    end
  end
end
