# frozen_string_literal: true

module Tasks
  # robot-tasks 3.5 (§3.5) — exclui uma tarefa.
  #
  # SOFT-DELETE (progress-advances D-IMUT/Q1): a trilha de avanços é imutável e a
  # FK `task_advances → tasks` é `ON DELETE RESTRICT`, então uma tarefa nunca é
  # apagada de verdade — some da leitura por `deleted_at` (o `default_scope` do
  # model a exclui). As atribuições são removidas explicitamente (o CASCADE só
  # dispararia num hard delete, que não acontece mais) para não deixar chip órfão
  # em "Minhas Tarefas".
  class DeleteService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(id:)
      task = ::Task.find_by(id: id)
      return error_response('not_found', 404) if task.nil?

      ::Task.transaction do
        ::TaskAssignee.where(task_id: task.id).delete_all
        task.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        # progress-rollup 2.3 — excluir a última tarefa Concluído leva o cache do
        # robô de 100 para 0 (robô sem tarefas), na mesma transação.
        ::Progress::CascadeRecompute.call(robot_id: task.robot_id)
      end
      success_response({}, 204)
    end
  end
end
