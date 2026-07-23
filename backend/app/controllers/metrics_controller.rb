# frozen_string_literal: true

require 'sidekiq/api'

# Métricas em formato Prometheus (delivery-and-observability 4.4). Protegido por
# `METRICS_TOKEN` (Bearer) — chamada sem token responde 401 SEM vazar um valor. NÃO
# usa `workspace_id` como label: 300 workspaces não podem virar 300 séries por
# métrica (cardinalidade explosiva). Rota Rails, antes do Grape, sem JWT.
class MetricsController < ActionController::API
  before_action :authenticate_metrics_token!

  def index
    render plain: prometheus_text, content_type: 'text/plain; version=0.0.4'
  end

  private

  def authenticate_metrics_token!
    expected = ENV['METRICS_TOKEN'].to_s
    provided = request.headers['Authorization'].to_s.sub(/\ABearer\s+/, '')
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  def prometheus_text
    m = collect
    [
      '# HELP robotrack_sidekiq_queue_depth Jobs enfileirados aguardando processamento.',
      '# TYPE robotrack_sidekiq_queue_depth gauge',
      "robotrack_sidekiq_queue_depth #{m[:queue_depth]}",
      '# HELP robotrack_sidekiq_retry_depth Jobs no conjunto de retry.',
      '# TYPE robotrack_sidekiq_retry_depth gauge',
      "robotrack_sidekiq_retry_depth #{m[:retry_depth]}",
      '# HELP robotrack_sidekiq_dead_depth Jobs no conjunto morto (dead set).',
      '# TYPE robotrack_sidekiq_dead_depth gauge',
      "robotrack_sidekiq_dead_depth #{m[:dead_depth]}",
      '# HELP robotrack_cable_connections Conexões ActionCable ativas neste processo.',
      '# TYPE robotrack_cable_connections gauge',
      "robotrack_cable_connections #{m[:cable_connections]}",
      '# HELP robotrack_workspaces_total Total de workspaces.',
      '# TYPE robotrack_workspaces_total gauge',
      "robotrack_workspaces_total #{m[:workspaces_total]}",
      ''
    ].join("\n")
  end

  def collect
    {
      queue_depth: safe { Sidekiq::Stats.new.enqueued },
      retry_depth: safe { Sidekiq::Stats.new.retry_size },
      dead_depth: safe { Sidekiq::Stats.new.dead_size },
      cable_connections: safe { ActionCable.server.connections.size },
      workspaces_total: safe { Workspace.count }
    }
  end

  def safe
    yield
  rescue StandardError
    0
  end
end
