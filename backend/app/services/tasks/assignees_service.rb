# frozen_string_literal: true

module Tasks
  # robot-tasks 4.1–4.3 (§3.5, §2.7, D-RT-6, D11) — substitui o CONJUNTO de
  # responsáveis de uma tarefa (PUT de conjunto, não deltas por item).
  #
  # O diff `{added, removed}` é calculado no servidor: insere quem entrou, remove
  # quem saiu, numa transação. Reenviar o MESMO conjunto (retry da fila offline)
  # é inócuo — `added` e `removed` vazios, nada muda. `person_ids` vazio zera os
  # responsáveis (D11: ausência é conjunto vazio, nunca "Não Atribuído").
  #
  # `person_id` de outro workspace é linha invisível pela RLS → 404, sem vazar
  # existência (§4.1 inv. 1). O evento `task.assignees_changed` leva o diff para
  # `in-app-notifications` (só `added` é notificado — quem já era responsável não
  # reaparece) e `realtime-collaboration`; a decisão de notificar é deles.
  class AssigneesService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def replace(task_id:, person_ids:)
      task = ::Task.find_by(id: task_id)
      return error_response('not_found', 404) if task.nil?

      # `reject(&:empty?)`: um `person_id` em branco é lixo — nunca um id válido.
      # Também absorve o caso do conjunto vazio chegar como `[""]` por
      # form-encoding (a UI manda JSON, mas a fila offline e testes variam).
      requested = Array(person_ids).map { |pid| pid.to_s.strip }.reject(&:empty?).uniq

      # Pessoas do workspace (a RLS escopa). Faltante = inexistente OU de outro
      # workspace → 404 uniforme (D-RT-6).
      found = ::Person.where(id: requested).pluck(:id).map(&:to_s)
      missing = requested - found
      return error_response('not_found', 404) if missing.any?

      current = ::TaskAssignee.where(task_id: task.id).pluck(:person_id).map(&:to_s)
      added = requested - current
      removed = current - requested

      ActiveRecord::Base.transaction do
        ::TaskAssignee.where(task_id: task.id, person_id: removed).delete_all if removed.any?
        if added.any?
          ::TaskAssignee.insert_all!(
            added.map { |pid| { task_id: task.id, person_id: pid, workspace_id: task.workspace_id } }
          )
        end
      end

      publish_event(task, added, removed)
      success_response({ added: added, removed: removed }, 200)
    end

    private

    # Sem mudança, sem evento (o re-PUT idempotente não gera ruído). O payload
    # leva SÓ o diff — quem já era responsável não entra em `added` (4.3).
    def publish_event(task, added, removed)
      return if added.empty? && removed.empty?

      ActiveSupport::Notifications.instrument(
        'task.assignees_changed',
        task_id: task.id, robot_id: task.robot_id, workspace_id: task.workspace_id,
        added: added, removed: removed, actor_person_id: @context&.person&.id
      )
    end
  end
end
