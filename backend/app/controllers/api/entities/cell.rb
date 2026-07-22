# frozen_string_literal: true

module Api
  module Entities
    # commissioning-hierarchy 4.4 (§1.4, D-H11).
    class Cell < Grape::Entity
      expose :id
      expose :project_id
      expose :name
      expose :position
      expose :lock_version
      expose :updated_at
      expose :updated_by_person_id

      # progress-rollup 3.1 (D15) — envelope rotulado do ponderado.
      expose :weighted_progress do |cell, _|
        ProgressMetric.weighted(cell.progress_cache)
      end

      expose :robots, using: Api::Entities::Robot do |cell, _|
        cell.robots.order(:position).to_a
      end
    end
  end
end
