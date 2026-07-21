# frozen_string_literal: true

module Tasks
  # robot-tasks 3.3/3.4 (§3.5, D-RT-3, D-RT-7) — edita a DESCRIÇÃO de uma tarefa.
  #
  # `progress`/`status` NÃO passam por aqui: o endpoint rejeita com 422 qualquer
  # payload que os contenha (a máquina de estados §2.2 é de `progress-advances`).
  # `lock_version` divergente → 409 com o estado atual no corpo, para o cliente
  # reconciliar (optimistic locking, D-RT-7).
  class UpdateService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(id:, lock_version:, desc: nil)
      task = ::Task.find_by(id: id)
      return error_response('not_found', 404) if task.nil?

      if lock_version && task.lock_version != lock_version.to_i
        return error_response('stale_object', 409, details: snapshot(task))
      end

      task.desc = desc unless desc.nil?
      task.save!
      success_response({ record: task }, 200)
    rescue ActiveRecord::StaleObjectError
      error_response('stale_object', 409, details: snapshot(task.reload))
    rescue ActiveRecord::RecordInvalid => e
      error_response('validation_error', 422, details: e.record.errors.messages)
    rescue ActiveRecord::RecordNotUnique
      error_response('desc_conflict', 409)
    end

    private

    def snapshot(task)
      { id: task.id, desc: task.desc, position: task.position,
        progress: task.progress, status: task.status, lock_version: task.lock_version }
    end
  end
end
