# frozen_string_literal: true

# Sondas de orquestrador (delivery-and-observability 2.3). Rotas Rails PÚBLICAS,
# montadas ANTES do Grape (senão o mount em '/' as engoliria), sem passar pelo
# before-hook de autenticação da API e sem depender do header `X-Skip-Auth`.
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
    !ActiveRecord::Base.connection.migration_context.needs_migration?
  rescue StandardError
    false
  end
end
