# frozen_string_literal: true

module Api
  module Entities
    # robot-tasks 3.1 (§3.5, §1.1, D10/D11) — a Tarefa como a tabela do robô a lê.
    #
    # `assignees` é `[{id, name}]` — identidade, não nome solto (D11). Tarefa sem
    # responsável sai como `[]`, nunca com um item "Não Atribuído". `progress` e
    # `status` aparecem para leitura, mas nenhum endpoint desta capacidade os
    # muta (D-RT-3). `weight` sai inteiro quando integral.
    class Task < Grape::Entity
      expose :id
      expose :robot_id
      expose :cat
      expose :desc
      expose(:weight) { |t, _| t.weight == t.weight.to_i ? t.weight.to_i : t.weight.to_f }
      expose :progress
      expose :status
      expose :position
      expose :lock_version
      expose :updated_at
      expose(:assignees) { |t, _| t.assignees.map { |p| { id: p.id, name: p.name } } }
    end
  end
end
