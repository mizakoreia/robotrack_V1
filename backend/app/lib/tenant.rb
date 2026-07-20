# frozen_string_literal: true

# tenant-isolation §"Contexto de tenant setado por request" (tarefa 3.2 / D-3).
#
# Abre uma transação e emite `set_config(..., true)` — o terceiro argumento
# `true` é `is_local`, então o valor morre no COMMIT/ROLLBACK. Este é o ponto:
# um `SET` não-local com reset num `ensure` devolveria a conexão SUJA ao pool em
# qualquer caminho que pulasse o `ensure` (Timeout, checkin do reaper), e o
# próximo request pegaria o tenant do request anterior — o exato bug de vazamento
# que esta camada existe para impedir. `SET LOCAL` não tem esse modo de falha: o
# fim da transação limpa, sempre.
#
# O thread-local guardado aqui é APENAS ergonômico (o concern WorkspaceScoped o
# lê para auto-atribuir `workspace_id`); NÃO é a fronteira de segurança — essa é
# a variável de sessão do Postgres. Por isso resetá-lo no `ensure` é seguro: não
# é ele que protege os dados.
module Tenant
  class << self
    def with(workspace_id:, user_id:)
      previous = Thread.current[:tenant_workspace_id]
      ActiveRecord::Base.transaction do
        conn = ActiveRecord::Base.connection
        conn.execute(
          "SELECT set_config('app.current_workspace_id', #{conn.quote(workspace_id.to_s)}, true), " \
          "set_config('app.current_user_id', #{conn.quote(user_id.to_s)}, true)"
        )
        Thread.current[:tenant_workspace_id] = workspace_id.to_s
        yield
      end
    ensure
      Thread.current[:tenant_workspace_id] = previous
    end

    # workspace_id do contexto corrente (thread-local ergonômico), ou nil.
    def current_workspace_id
      Thread.current[:tenant_workspace_id]
    end
  end
end
