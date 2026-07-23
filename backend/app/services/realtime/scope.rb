# frozen_string_literal: true

module Realtime
  # realtime-collaboration D6.3 — resolve a cadeia de ancestrais (projeto, célula,
  # robô) que o `scope` do envelope carrega para a invalidação de rollup. As
  # tabelas só denormalizam o pai imediato (`tasks.robot_id`, `robots.cell_id`,
  # `cells.project_id`), então subimos por `pick` — com `unscoped`, porque um
  # ancestral arquivado (soft-delete) ainda precisa nomear as chaves a invalidar.
  # Roda dentro do contexto de tenant reaberto pelo `PublisherService` (RLS ativa).
  module Scope
    module_function

    def for_robot(robot_id)
      return { robot_id: robot_id } if robot_id.blank?

      cell_id = Robot.unscoped.where(id: robot_id).pick(:cell_id)
      project_id = cell_id && Cell.unscoped.where(id: cell_id).pick(:project_id)
      { project_id: project_id, cell_id: cell_id, robot_id: robot_id }
    end

    def for_task(task_id)
      return {} if task_id.blank?

      for_robot(Task.unscoped.where(id: task_id).pick(:robot_id))
    end
  end
end
