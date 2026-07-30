# frozen_string_literal: true

# notification-preferences G6 (§D-P8). Job best-effort do evento estrutural
# (criar/excluir na hierarquia). `workspace_id` é o PRIMEIRO argumento (o
# middleware de tenant do Sidekiq abre o contexto RLS a partir dele). Fila
# própria `:notifications`, retry 5; no esgotamento vai para a dead set — nunca
# retenta infinitamente (D-N7). O payload já vem MATERIALIZADO (label/parent/ctx
# capturados no disparo), então o job só resolve destinatários e insere.
class NotifyStructureEventJob < ApplicationJob
  queue_as :notifications
  sidekiq_options retry: 5 if respond_to?(:sidekiq_options)

  def perform(_workspace_id, payload)
    p = payload.symbolize_keys
    Notifications::CreateService.for_structure(
      workspace_id: p[:workspace_id], actor_person_id: p[:actor_person_id], author: p[:author],
      entity: p[:entity], action: p[:action], label: p[:label], parent: p[:parent],
      ctx: p[:ctx], recorded_at: p[:recorded_at]
    )
  end
end
