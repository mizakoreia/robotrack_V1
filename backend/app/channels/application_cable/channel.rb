# frozen_string_literal: true

module ApplicationCable
  # workspace-tenancy 4.4 / D-6: contexto de tenant no ActionCable.
  #
  # A Connection já identifica `current_user`. Aqui a base de canal oferece a
  # resolução de tenant que todo canal de workspace (WorkspaceChannel, a jusante
  # em realtime-collaboration) usa: resolve o papel no servidor e REJEITA a
  # subscrição de um workspace alheio. Trabalho de banco dentro do canal roda em
  # `with_tenant`, que abre o mesmo `Tenant.with` (SET LOCAL em transação) do HTTP.
  class Channel < ActionCable::Channel::Base
    # Resolve o papel do usuário no workspace; rejeita a subscrição se ele não
    # pertence (mesma regra do HTTP: alheio e inexistente são indistinguíveis).
    # Devolve o Result em caso de sucesso, ou nil após rejeitar.
    def resolve_workspace_or_reject(workspace_id)
      resolution = ActiveRecord::Base.transaction do
        Workspaces::ResolveCurrentService.new(user: current_user, workspace_id: workspace_id).call
      end

      unless resolution.ok
        reject
        return nil
      end

      @current_workspace_id = resolution.workspace_id
      @current_role = resolution.role
      resolution
    end

    # Executa DB work no contexto de tenant do workspace já resolvido.
    def with_tenant(&block)
      Tenant.with(workspace_id: current_workspace_id, user_id: current_user.id, &block)
    end

    def current_user
      connection.current_user
    end

    attr_reader :current_workspace_id, :current_role
  end
end
