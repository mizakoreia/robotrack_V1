# frozen_string_literal: true

module Workspaces
  # workspace-core §"Seleção do workspace corrente por request" (tarefa 4.1).
  #
  # Lê o workspace pedido (`X-Workspace-Id`), valida pertencimento e resolve o
  # papel NO SERVIDOR — nunca a partir do cliente. `owner` é derivado de
  # `owner_user_id`; senão, a `role` da membership; senão, sem acesso.
  #
  # Anti-enumeração de WORKSPACES: header ausente é `400 workspace_context_missing`;
  # workspace alheio E workspace inexistente devolvem ambos `403
  # workspace_access_denied` — a diferença de status vazaria a existência do
  # tenant. (A anti-enumeração de RECURSOS de outro tenant é outra camada: a RLS
  # os torna 404 via RecordNotFound.)
  #
  # Precisa estar dentro de uma transação: seta `app.current_user_id` (SET LOCAL)
  # para que a política de controle de `workspaces` deixe ver os workspaces que o
  # usuário possui ou é membro. Se o workspace não estiver visível por essa
  # política, ele não pertence ao usuário → 403.
  class ResolveCurrentService
    Result = Struct.new(:ok, :status, :error, :workspace_id, :role, keyword_init: true)

    def initialize(user:, workspace_id:)
      @user = user
      @workspace_id = workspace_id.presence
    end

    def call
      return failure(400, 'workspace_context_missing') if @workspace_id.nil?

      Tenant.set_user!(@user.id)

      workspace = Workspace.where(id: @workspace_id).first
      return failure(403, denial_code) if workspace.nil?

      role = resolve_role(workspace)
      return failure(403, denial_code) if role.nil?

      Result.new(ok: true, workspace_id: workspace.id, role: role)
    rescue ActiveRecord::StatementInvalid
      # X-Workspace-Id malformado (uuid inválido) não revela nada além de negação.
      failure(403, 'workspace_access_denied')
    end

    private

    # workspace-invitations 5.3 / D-INV-7 — o fallback de revogação.
    #
    # A negação continua sendo SEMPRE 403, e continua indistinguível entre
    # "workspace alheio" e "workspace inexistente" — é o que impede enumerar
    # tenants (Onda 1). O código diferenciado só aparece para quem TEVE acesso e
    # o perdeu, e essa pessoa já sabia que o workspace existe: nada novo vaza.
    # Sem isto, o cliente de quem foi removido não teria como distinguir "fui
    # expulso daqui" de "digitei o workspace errado", e §3.10 exige avisá-lo.
    def denial_code
      revoked? ? 'workspace_access_revoked' : 'workspace_access_denied'
    end

    def revoked?
      MembershipRevocation.unscoped
                          .where(workspace_id: @workspace_id, user_id: @user.id)
                          .exists?
    rescue ActiveRecord::StatementInvalid
      false
    end

    def resolve_role(workspace)
      return :owner if workspace.owner_user_id == @user.id

      Membership.where(workspace_id: workspace.id, user_id: @user.id).first&.role&.to_sym
    end

    def failure(status, error)
      Result.new(ok: false, status: status, error: error)
    end
  end
end
