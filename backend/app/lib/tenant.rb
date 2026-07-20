# frozen_string_literal: true

# tenant-isolation §"Contexto de tenant setado por request" (tarefas 3.2, 4.x / D-3).
#
# `set_config(..., true)` é `SET LOCAL`: o valor morre no COMMIT/ROLLBACK. Este é
# o ponto — um `SET` não-local com reset num `ensure` devolveria a conexão SUJA
# ao pool em qualquer caminho que pulasse o `ensure` (Timeout, checkin do reaper),
# e o próximo request pegaria o tenant do anterior. `SET LOCAL` não tem esse modo
# de falha: o fim da transação limpa, sempre.
#
# Dois modos de uso:
#   - `Tenant.with(...)` abre a própria transação (Sidekiq, ActionCable, specs).
#   - `Tenant.apply!(...)` assume que JÁ existe transação (o request HTTP: o
#     middleware TenantTransaction abre a transação e o bloco `before` do Grape
#     chama apply! dentro dela).
#
# O thread-local é APENAS ergonômico (o concern WorkspaceScoped o lê para
# auto-atribuir `workspace_id`); NÃO é a fronteira de segurança — essa é a
# variável de sessão do Postgres. Resetá-lo no `ensure` é seguro: não é ele que
# protege os dados.
module Tenant
  class << self
    def with(workspace_id:, user_id:)
      previous = Thread.current[:tenant_workspace_id]
      ActiveRecord::Base.transaction do
        apply!(workspace_id: workspace_id, user_id: user_id)
        yield
      end
    ensure
      Thread.current[:tenant_workspace_id] = previous
    end

    # Emite o SET LOCAL das duas variáveis de sessão. Precisa estar dentro de uma
    # transação (senão o Postgres ignora o SET LOCAL). Seta o thread-local.
    def apply!(workspace_id:, user_id:)
      set_config('app.current_workspace_id', workspace_id)
      set_config('app.current_user_id', user_id)
      Thread.current[:tenant_workspace_id] = workspace_id.to_s
      nil
    end

    # Seta só o usuário corrente — usado pela resolução do workspace, que precisa
    # ler `workspaces`/`memberships` (políticas de controle) ANTES de haver tenant.
    def set_user!(user_id)
      set_config('app.current_user_id', user_id)
    end

    def current_workspace_id
      Thread.current[:tenant_workspace_id]
    end

    def reset_thread_context!
      Thread.current[:tenant_workspace_id] = nil
    end

    private

    def set_config(name, value)
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT set_config(#{conn.quote(name)}, #{conn.quote(value.to_s)}, true)")
    end
  end
end
