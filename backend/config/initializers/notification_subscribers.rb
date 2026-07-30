# frozen_string_literal: true

# Liga os eventos de domínio à fila de notificações (in-app-notifications 4.3). Os
# `publish_event` de progress-advances e robot-tasks instrumentam DEPOIS do commit
# (fora da transação) — então enfileirar aqui é after_commit por construção: um
# rollback do avanço nunca chega a instrumentar, logo enfileira ZERO jobs. O
# enfileiramento é best-effort: Redis fora não pode derrubar o save (4.4), então
# a falha é logada e engolida.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('task.advanced') do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    NotifyTaskEventJob.perform_later(payload[:workspace_id], 'advance', { advance_id: payload[:advance_id] })
  rescue StandardError => e
    Rails.logger.error({ event: 'notify_enqueue_failed', kind: 'advance', error: e.message }.to_json)
  end

  ActiveSupport::Notifications.subscribe('task.assignees_changed') do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    next if Array(payload[:added]).empty?

    NotifyTaskEventJob.perform_later(
      payload[:workspace_id], 'assign',
      { task_id: payload[:task_id], added: payload[:added], actor_person_id: payload[:actor_person_id],
        recorded_at: Time.current.utc.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.error({ event: 'notify_enqueue_failed', kind: 'assign', error: e.message }.to_json)
  end

  # notification-preferences G6 (§D-P8) — evento estrutural (criar/excluir
  # projeto/célula/robô/tarefa). `Notifications::StructureEvent.publish` já
  # instrumenta DEPOIS do commit da operação de hierarquia; um rollback nunca
  # chega a instrumentar, logo enfileira ZERO jobs. `recorded_at` é fixado AQUI,
  # no enfileiramento (como o `assign`), para um retry do job não deslocar o
  # carimbo. O payload carrega o texto-fonte materializado (label/parent/ctx).
  ActiveSupport::Notifications.subscribe('structure.changed') do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    NotifyStructureEventJob.perform_later(
      payload[:workspace_id],
      { workspace_id: payload[:workspace_id], actor_person_id: payload[:actor_person_id],
        author: payload[:author], entity: payload[:entity], action: payload[:action],
        label: payload[:label], parent: payload[:parent], ctx: payload[:ctx],
        recorded_at: Time.current.utc.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.error({ event: 'notify_enqueue_failed', kind: 'structure', error: e.message }.to_json)
  end
end
