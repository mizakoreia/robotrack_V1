# frozen_string_literal: true

# Liga os eventos de domínio à criação de notificações (in-app-notifications 4.3).
#
# EXECUÇÃO INLINE (perform_now), não enfileirada (perform_later). Motivo: no PLANO
# FREE do Render o Sidekiq roda EMBUTIDO no web e o dyno HIBERNA — o worker é
# frágil/indisponível (jobs ficam parados na fila e a notificação nunca sai). Como
# os `publish_event`/`StructureEvent.publish` já instrumentam DEPOIS do commit
# (fora da transação) e DENTRO da requisição, o contexto de tenant do requisitante
# já está aberto: criar a notificação AQUI, na hora, roda no workspace certo, sob
# RLS, sem depender do worker. Um rollback nunca chega a instrumentar (zero
# notificação). É best-effort: qualquer erro é logado e engolido — NUNCA derruba a
# escrita (avanço/atribuição/estrutural). Reverter para `perform_later` quando
# houver um Background Worker dedicado (plano pago).
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('task.advanced') do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    NotifyTaskEventJob.perform_now(payload[:workspace_id], 'advance', { advance_id: payload[:advance_id] })
  rescue StandardError => e
    Rails.logger.error({ event: 'notify_inline_failed', kind: 'advance', error: e.message }.to_json)
  end

  ActiveSupport::Notifications.subscribe('task.assignees_changed') do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    next if Array(payload[:added]).empty?

    NotifyTaskEventJob.perform_now(
      payload[:workspace_id], 'assign',
      { task_id: payload[:task_id], added: payload[:added], actor_person_id: payload[:actor_person_id],
        recorded_at: Time.current.utc.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.error({ event: 'notify_inline_failed', kind: 'assign', error: e.message }.to_json)
  end

  # notification-preferences G6 (§D-P8) — evento estrutural (criar/excluir
  # projeto/célula/robô/tarefa). `Notifications::StructureEvent.publish` já
  # instrumenta DEPOIS do commit da operação de hierarquia; um rollback nunca
  # chega a instrumentar. `recorded_at` é fixado AQUI. O payload carrega o
  # texto-fonte materializado (label/parent/ctx).
  ActiveSupport::Notifications.subscribe('structure.changed') do |*args|
    payload = ActiveSupport::Notifications::Event.new(*args).payload
    NotifyStructureEventJob.perform_now(
      payload[:workspace_id],
      { workspace_id: payload[:workspace_id], actor_person_id: payload[:actor_person_id],
        author: payload[:author], entity: payload[:entity], action: payload[:action],
        label: payload[:label], parent: payload[:parent], ctx: payload[:ctx],
        recorded_at: Time.current.utc.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.error({ event: 'notify_inline_failed', kind: 'structure', error: e.message }.to_json)
  end
end
