# frozen_string_literal: true

module Tenant
  # tenant-isolation §"Contexto de tenant" (tarefa 4.3 / D-3).
  #
  # Todo job de DOMÍNIO carrega `workspace_id` como primeiro argumento e declara
  # `sidekiq_options tenant: true`. Este middleware de servidor abre o
  # `Tenant.with` a partir desse argumento. Um job de domínio enfileirado SEM o
  # workspace_id é erro de programação: o middleware levanta ANTES do `perform`,
  # e o job vai para a fila de mortos em vez de rodar com contexto nulo (e
  # portanto vazio/fail-closed, o que mascararia o bug).
  #
  # Jobs não marcados (mailers, manutenção) passam direto — a decisão de ser
  # tenant-scoped é explícita, nunca implícita.
  class SidekiqServerMiddleware
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def call(worker, job, _queue, &block)
      return yield unless tenant_scoped?(worker)

      workspace_id = job['args']&.first
      unless workspace_id.is_a?(String) && workspace_id.match?(UUID)
        raise ArgumentError,
              "job de domínio #{worker.class} exige workspace_id (uuid) como primeiro " \
              "argumento; recebeu #{workspace_id.inspect}"
      end

      Tenant.with(workspace_id: workspace_id, user_id: nil, &block)
    end

    private

    def tenant_scoped?(worker)
      worker.class.respond_to?(:get_sidekiq_options) &&
        worker.class.get_sidekiq_options['tenant'] == true
    end
  end
end
