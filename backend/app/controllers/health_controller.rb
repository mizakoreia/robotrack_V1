# frozen_string_literal: true

# Sondas de orquestrador (delivery-and-observability 2.3). Rotas Rails PÚBLICAS,
# montadas ANTES do Grape (senão o mount em '/' as engoliria), sem passar pelo
# before-hook de autenticação da API e sem depender de nenhum header de bypass.
#
# Distinção que importa:
#   /health/live  — "o processo está vivo?" — NÃO toca dependências. É o que o
#                   HEALTHCHECK do container usa; se checasse o Postgres, uma queda
#                   do banco reiniciaria todos os web em laço.
#   /health/ready — "posso receber tráfego?" — checa Postgres, Redis de fila e
#                   migrations pendentes. Com o Postgres fora, /live=200 e
#                   /ready=503, e o balanceador tira o pod da rotação sem matá-lo.
class HealthController < ActionController::API
  def live
    render json: { status: 'ok' }, status: :ok
  end

  def ready
    checks = {
      database: database_ok?,
      redis_queue: redis_queue_ok?,
      migrations: migrations_current?
    }
    healthy = checks.values.all?
    render json: { status: healthy ? 'ok' : 'degraded', checks: checks },
           status: healthy ? :ok : :service_unavailable
  end

  # DIAGNÓSTICO TEMPORÁRIO — o Sidekiq roda EMBUTIDO no web (free tier); sem acesso
  # aos logs do Render, este endpoint mostra se ele está vivo e se a fila drena.
  # `processes` = quantos processos Sidekiq batem heartbeat; se 0, o worker não
  # está rodando. `queues` = tamanho por fila; se `notifications` acumula, os jobs
  # não são consumidos. Só contagens (nada sensível). REMOVER após diagnosticar.
  def sidekiq_diag
    require 'sidekiq/api'
    stats = Sidekiq::Stats.new
    render json: {
      processes: Sidekiq::ProcessSet.new.size,
      process_queues: Sidekiq::ProcessSet.new.map { |p| p['queues'] },
      queues: Sidekiq::Queue.all.to_h { |q| [q.name, q.size] },
      enqueued: stats.enqueued,
      retry_set: Sidekiq::RetrySet.new.size,
      dead_set: Sidekiq::DeadSet.new.size,
      processed: stats.processed,
      failed: stats.failed
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.class.name, message: e.message }, status: :ok
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.execute('SELECT 1')
    true
  rescue StandardError
    false
  end

  def redis_queue_ok?
    Sidekiq.redis { |conn| conn.ping } == 'PONG'
  rescue StandardError
    false
  end

  def migrations_current?
    # Rails 8.0 moveu `migration_context` do connection para o connection_pool;
    # `connection.migration_context` levanta NoMethodError (engolido pelo rescue),
    # o que fazia /health/ready reportar migrations desatualizadas PARA SEMPRE e o
    # deploy nunca ficar ready (BUG 4).
    !ActiveRecord::Base.connection_pool.migration_context.needs_migration?
  rescue StandardError
    false
  end
end
