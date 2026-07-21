# frozen_string_literal: true

module Authorization
  # Contexto imutável de autorização, construído UMA vez por request (D3.3).
  #
  # O papel é resolvido AQUI, no servidor, e em nenhum outro lugar: dono pela
  # coluna `workspaces.owner_user_id` (o mecanismo da Onda 1 — trigger
  # `workspaces_owner_immutable` + `memberships_owner_is_not_member` garantem
  # exatamente um dono, imutável), senão `memberships.role`. O construtor NÃO
  # aceita `role` por argumento: nenhum chamador injeta papel, nenhum claim de
  # JWT ou índice de UI participa (§4.1 inv. 2).
  #
  # Sem membership e sem posse, `role` é nil e toda policy nega — a resposta
  # HTTP para não-membro é 404, não 403 (D3.6).
  class Context
    attr_reader :user, :workspace, :person, :role

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
      @person = resolve_person
      @role = resolve_role
      freeze
    end

    def member?
      !role.nil?
    end

    private

    def resolve_person
      return nil unless user && workspace

      Person.find_by(workspace_id: workspace.id, user_id: user.id)
    end

    def resolve_role
      return nil unless user && workspace
      return :owner if workspace.owner_user_id == user.id

      Membership.find_by(workspace_id: workspace.id, user_id: user.id)&.role&.to_sym
    end
  end
end
