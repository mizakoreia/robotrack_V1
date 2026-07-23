# frozen_string_literal: true

# Job best-effort de notificação (in-app-notifications 4.2). `workspace_id` é o
# PRIMEIRO argumento (o middleware de tenant abre o contexto a partir dele). Fila
# própria `:notifications`, retry 5; no esgotamento, reporta estruturado e vai para
# a dead set — nunca retenta infinitamente (D-N7).
class NotifyTaskEventJob < ApplicationJob
  queue_as :notifications
  sidekiq_options retry: 5 if respond_to?(:sidekiq_options)

  # kind: 'advance' | 'assign'. payload: hash simbolizado.
  def perform(_workspace_id, kind, payload)
    p = payload.symbolize_keys
    case kind.to_s
    when 'advance'
      Notifications::CreateService.for_advance(advance_id: p[:advance_id])
    when 'assign'
      Notifications::CreateService.for_assign(task_id: p[:task_id], added: p[:added],
                                              actor_person_id: p[:actor_person_id], recorded_at: p[:recorded_at])
    end
  end
end
