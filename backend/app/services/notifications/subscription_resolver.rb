# frozen_string_literal: true

module Notifications
  # notification-preferences G2 (D-P3/D-P4/D-P5). Resolve as preferências de um
  # galho `(project, cell, robot)` e decide, por pessoa, se ela quer receber —
  # regra "o mais específico vence" (robô > célula > projeto); sem linha → DEFAULT.
  #
  # Objeto PURO sobre um índice pré-carregado: `load(ctx)` faz UMA query e devolve
  # `person_id => { level:, state: }` já reduzido ao nível mais específico. O
  # `CreateService` monta candidatos∪seguidores, subtrai o autor e filtra por
  # `wants?` — a ordem sagrada do pipeline (dedup, nunca-o-autor) fica intacta.
  module SubscriptionResolver
    module_function

    ROBOT_LEVEL = 2
    CELL_LEVEL = 1
    PROJECT_LEVEL = 0

    # Carrega as linhas relevantes ao galho numa única consulta e reduz ao nível
    # mais específico por pessoa. Roda no contexto de tenant do job (RLS).
    def load(ctx)
      rows = ::NotificationSubscription
             .where('scope_project_id = :p OR scope_cell_id = :c OR scope_robot_id = :r',
                    p: ctx[:project_id], c: ctx[:cell_id], r: ctx[:robot_id])
             .pluck(:person_id, :scope_project_id, :scope_cell_id, :scope_robot_id, :state)

      index = {}
      rows.each do |person_id, proj, cell, robot, state|
        level = if robot then ROBOT_LEVEL elsif cell then CELL_LEVEL else PROJECT_LEVEL end
        pid = person_id.to_s
        current = index[pid]
        index[pid] = { level: level, state: state } if current.nil? || level > current[:level]
      end
      index
    end

    # Pessoas cujo nível mais específico é `follow` — candidatas a entrar como
    # seguidoras mesmo sem serem responsáveis. Quem tem `mute` no nível mais
    # específico NÃO é seguidor, ainda que siga um pai.
    def followers(index)
      index.select { |_pid, entry| entry[:state] == 'follow' }.keys
    end

    # `follow` no nível mais específico → recebe; `mute` → não recebe; sem linha →
    # o DEFAULT do chamador (responsável/dono).
    def wants?(person_id, index, default:)
      entry = index[person_id.to_s]
      return default if entry.nil?

      entry[:state] == 'follow'
    end

    # Aplica o filtro a um conjunto de candidatos-default: adiciona seguidores,
    # subtrai o autor (nunca o autor, mesmo seguidor) e mantém só quem `wants?`.
    def filter(default_recipients, index, actor_id)
      default_set = default_recipients.map(&:to_s).to_set
      universe = (default_recipients.map(&:to_s) + followers(index)).uniq
      universe -= [actor_id.to_s]
      universe.select { |pid| wants?(pid, index, default: default_set.include?(pid)) }
    end
  end
end
