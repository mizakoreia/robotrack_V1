# frozen_string_literal: true

module Tasks
  # robot-tasks 3.5 (§3.5) — exclui uma tarefa. As linhas de `task_assignees`
  # somem com ela pelo `ON DELETE CASCADE` da FK — sem órfãs.
  class DeleteService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(id:)
      task = ::Task.find_by(id: id)
      return error_response('not_found', 404) if task.nil?

      task.destroy!
      success_response({}, 204)
    end
  end
end
