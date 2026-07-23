# frozen_string_literal: true

module Api
  module Entities
    # in-app-notifications 5.1 (D-N2). A `msg` já vem renderizada e truncada do
    # servidor; o cliente exibe. `ctx` são as quatro colunas (não jsonb) para a
    # navegação de 6.3. Ordenação sempre `recorded_at DESC`.
    class Notification < Grape::Entity
      expose :id
      expose :type
      expose :msg
      expose :author_name_snapshot
      expose :recorded_at
      expose :created_at
      expose :ts_local
      expose :read
      expose :read_at
      expose :ctx do
        expose :ctx_project_id, as: :project_id
        expose :ctx_cell_id, as: :cell_id
        expose :ctx_robot_id, as: :robot_id
        expose :ctx_task_id, as: :task_id
      end
    end
  end
end
