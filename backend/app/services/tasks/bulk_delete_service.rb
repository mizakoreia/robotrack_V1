# frozen_string_literal: true

module Tasks
  # robot-task-grouping G2 (D-TG-6/7) — exclui VÁRIAS tarefas de uma vez.
  #
  # SOFT-DELETE em lote, mesmo contrato da exclusão individual (Tasks::DeleteService):
  # a trilha de avanços é imutável e a FK `task_advances → tasks` é `ON DELETE RESTRICT`,
  # então nada é apagado de verdade — as linhas ganham `deleted_at` e somem da leitura
  # (`default_scope`) e das views de progresso (todas filtram `deleted_at IS NULL`).
  #
  # Numa ÚNICA transação: remove os responsáveis das tarefas, faz o soft-delete com
  # `update_all` (sem callbacks → sem cascata por linha) e recalcula o rollup UMA VEZ
  # por robô distinto. NÃO uso `Progress.without_cascade` (aquele contrato exige terminar
  # em `BulkRecompute`, workspace-wide) porque o `update_all` já não dispara cascata:
  # basta chamar `CascadeRecompute` explicitamente por robô ao fim.
  #
  # RLS: `::Task.where(id:)` roda como `robotrack_app` e só enxerga o próprio workspace —
  # ids inexistentes ou de outro tenant simplesmente não entram no conjunto (ignorados,
  # sem vazar 404 por item). `deleted_count` conta só o que existia e era visível.
  class BulkDeleteService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(ids:)
      ids = Array(ids).map(&:to_s).uniq
      deleted = ids.empty? ? 0 : ::Task.transaction { soft_delete(ids) }
      success_response({ deleted_count: deleted }, 200)
    end

    private

    def soft_delete(ids)
      tasks = ::Task.where(id: ids).to_a # RLS + default_scope: só visível e não deletada
      return 0 if tasks.empty?

      task_ids = tasks.map(&:id)
      ::TaskAssignee.where(task_id: task_ids).delete_all
      count = ::Task.where(id: task_ids).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      # um recálculo por robô distinto (o update_all não dispara cascata por linha).
      tasks.map(&:robot_id).uniq.each { |robot_id| ::Progress::CascadeRecompute.call(robot_id: robot_id) }
      count
    end
  end
end
