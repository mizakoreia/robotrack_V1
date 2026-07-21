# frozen_string_literal: true

module Api
  module Entities
    # robot-tasks 3.1 (§3.5, §1.1, D10/D11) — a Tarefa como a tabela do robô a lê.
    #
    # `assignees` é `[{id, name}]` — identidade, não nome solto (D11). Tarefa sem
    # responsável sai como `[]`, nunca com um item "Não Atribuído". `progress` e
    # `status` aparecem para leitura, mas nenhum endpoint desta capacidade os
    # muta (D-RT-3). `weight` sai inteiro quando integral.
    #
    # progress-advances 4.3 (§3.5 coluna Trilha) — `advances_count` e
    # `last_comment` deixam `robot-task-table` montar o aviso "trilha faltando"
    # (`0 < progress < 100 AND advances_count = 0`) sem uma segunda consulta.
    # A ListService pré-carrega `task_advances`, então contar/ordenar aqui é em
    # memória (sem N+1). `last_comment` é o comentário do avanço mais recente pela
    # ordem da trilha (recorded_at, depois created_at, depois id).
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
      expose(:advances_count) { |t, _| t.task_advances.size }
      expose(:last_comment) do |t, _|
        t.task_advances.max_by { |a| [a.recorded_at, a.created_at, a.id] }&.comment
      end
    end
  end
end
