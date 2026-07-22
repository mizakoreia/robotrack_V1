# frozen_string_literal: true

module Api
  module Entities
    # commissioning-hierarchy 4.4 (§1.4, D-H11) — leitura tolerante é do
    # SERVIDOR: `cells` é sempre array (nunca null). O progresso ponderado sai no
    # envelope rotulado de progress-rollup (D15), lendo `progress_cache` smallint.
    class Project < Grape::Entity
      expose :id
      expose :name
      expose :position
      expose :lock_version
      expose :updated_at
      expose :updated_by_person_id

      expose :weighted_progress do |project, _|
        ProgressMetric.weighted(project.progress_cache)
      end

      expose :cells, using: Api::Entities::Cell do |project, _|
        project.cells.order(:position).to_a
      end
    end
  end
end
