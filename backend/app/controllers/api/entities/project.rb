# frozen_string_literal: true

module Api
  module Entities
    # commissioning-hierarchy 4.4 (§1.4, D-H11) — leitura tolerante é do
    # SERVIDOR: `cells` é sempre array (nunca null) e o cache vazio vira
    # `{weighted: 0, done: 0, total: 0}` — a tela nunca sabe que existe cache.
    class Project < Grape::Entity
      expose :id
      expose :name
      expose :position
      expose :lock_version
      expose :updated_at
      expose :updated_by_person_id

      expose :progress do |project, _|
        { 'weighted' => 0, 'done' => 0, 'total' => 0 }.merge(project.progress_cache || {})
      end

      expose :cells, using: Api::Entities::Cell do |project, _|
        project.cells.order(:position).to_a
      end
    end
  end
end
