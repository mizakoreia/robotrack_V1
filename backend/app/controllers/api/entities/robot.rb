# frozen_string_literal: true

module Api
  module Entities
    # commissioning-hierarchy 4.4 (§1.4, D-H11). `tasks` sai como array vazio e
    # `tasks_count` 0 até `robot-tasks` existir — "robô sem tarefas" nunca
    # quebra o render (§1.4), e hierarchy-screens pode nascer contra isto.
    class Robot < Grape::Entity
      expose :id
      expose :cell_id
      expose :name
      expose :application
      expose :position
      expose :lock_version
      expose :updated_at
      expose :updated_by_person_id

      expose :progress do |robot, _|
        { 'weighted' => 0, 'done' => 0, 'total' => 0 }.merge(robot.progress_cache || {})
      end

      expose(:tasks) { |_, _| [] }
      expose(:tasks_count) { |_, _| 0 }
    end
  end
end
