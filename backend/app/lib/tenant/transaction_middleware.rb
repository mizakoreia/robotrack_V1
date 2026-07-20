# frozen_string_literal: true

module Tenant
  # tenant-isolation §"Contexto de tenant" (tarefa 4.2 / D-3).
  #
  # Abre UMA transação em volta do endpoint de domínio, para que o `SET LOCAL`
  # emitido pelo bloco `before` do Grape (via Tenant.apply!) valha durante toda a
  # request e seja descartado no fim — commit ou rollback. Rotas sem tenant (a
  # allowlist de Api::Root) NÃO entram em transação (D-3, trade-off iii).
  #
  # O middleware só provê a transação; quem resolve e seta o contexto é o bloco
  # `before`, que roda DENTRO desta transação (o `use` do Grape envolve os
  # callbacks do endpoint).
  class TransactionMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) if Api::Root.tenant_exempt?(env['PATH_INFO'].to_s)

      response = nil
      ActiveRecord::Base.transaction { response = @app.call(env) }
      response
    ensure
      Tenant.reset_thread_context!
    end
  end
end
