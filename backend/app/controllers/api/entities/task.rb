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

      # robot-task-table 1.1 (§3.5, D-RTT-4/D8) — `contributors` = quem JÁ registrou
      # avanço (DISTINCT autor não-nulo; legacy sem autor não entra), conjunto
      # SEPARADO de `assignees` (responsável agora). `last_advance` traz a data de
      # AÇÃO `recorded_at` (D8, nunca `created_at`), o autor-snapshot e o marcador
      # `legacy`. Ambos em memória sobre os `task_advances` já pré-carregados (sem N+1).
      expose(:contributors) do |t, _|
        t.task_advances.reject { |a| a.by.nil? }
         .map { |a| { id: a.by, name: a.author_name_snapshot } }
         .uniq { |c| c[:id] }
      end
      expose(:last_advance) do |t, _|
        a = t.task_advances.max_by { |x| [x.recorded_at, x.created_at, x.id] }
        a && {
          comment: a.comment, recorded_at: a.recorded_at,
          author_name_snapshot: a.author_name_snapshot, legacy: a.legacy
        }
      end
    end
  end
end
