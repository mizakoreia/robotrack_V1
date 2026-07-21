# frozen_string_literal: true

module Memberships
  # team-access-management §"Mudança de papel de membro" (tarefa 4.1 /
  # invariante 5).
  #
  # Só o dono muda papel, e só entre `view` e `edit`. `owner` não é papel de
  # membership — é derivado de `workspaces.owner_user_id` (Onda 1) e é IMUTÁVEL.
  # Por isso há duas negações distintas, e elas dizem coisas diferentes:
  #
  #   - `invalid_role`      → você pediu um papel que não existe nesta tabela;
  #   - `owner_is_immutable` → o ALVO é o dono, e o dono não muda de papel.
  #
  # O alvo "dono" chega aqui como o `person_id` do dono (a listagem devolve o
  # dono com esse id, já que ele não tem linha de membership). Sem esse
  # tratamento, rebaixar o dono seria simplesmente `404` — verdadeiro, mas
  # inútil para a UI.
  class UpdateRoleService
    include ApiResponseHandler

    ALLOWED_ROLES = %w[view edit].freeze

    def initialize(current_user:, current_role:, workspace_id:, membership_id:, role:)
      @current_user = current_user
      @current_role = current_role
      @workspace_id = workspace_id
      @membership_id = membership_id
      @role = role.to_s
    end

    def call
      return error_response('forbidden', 403) unless MembershipPolicy.update?(::Authorization::RoleContext.new(@current_role))

      return error_response('invalid_role', 422) unless ALLOWED_ROLES.include?(@role)

      membership = find_membership
      if membership.nil?
        return error_response('owner_is_immutable', 422) if owner_row?
        return error_response('membership_not_found', 404)
      end

      membership.update!(role: @role)
      success_response({ id: membership.id, role: membership.role }, 200)
    end

    private

    def find_membership
      Membership.find_by(id: @membership_id)
    rescue ActiveRecord::StatementInvalid
      nil
    end

    # A linha do dono na listagem é a `Person` dele. Um `membership_id` que
    # aponte para ela (ou para o próprio usuário dono) é uma tentativa de mexer
    # no dono.
    def owner_row?
      owner_user_id = Workspace.where(id: @workspace_id).pick(:owner_user_id)
      return false if owner_user_id.nil?

      @membership_id.to_s == owner_user_id.to_s ||
        Person.where(id: @membership_id, user_id: owner_user_id).exists?
    rescue ActiveRecord::StatementInvalid
      false
    end
  end
end
