# frozen_string_literal: true

module Tasks
  # robot-tasks 3.1 (§3.5/§1.4) — as tarefas de um robô, ordenadas por `position`.
  # Robô sem tarefas devolve relação vazia (a tabela do robô mostra `tasks: []`,
  # nunca 404 — o 404 é do robô inexistente, tratado no endpoint).
  module ListService
    def self.for_robot(robot_id)
      ::Task.where(robot_id: robot_id).includes(:assignees).order(:position)
    end
  end
end
