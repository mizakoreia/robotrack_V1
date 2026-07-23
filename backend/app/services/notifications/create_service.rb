# frozen_string_literal: true

module Notifications
  # Compõe classifier + resolver + builder e insere as linhas (in-app-notifications
  # 4.1). Best-effort: tolera a violação do índice único de idempotência de assign
  # (1.5) SEM levantar — reexecutar com os mesmos parâmetros não cria segunda linha
  # e conclui com sucesso. Roda dentro do contexto de tenant do job.
  module CreateService
    module_function

    # Evento de avanço: classifica (from,to); progress/done → todos os responsáveis
    # atuais menos o autor.
    def for_advance(advance_id:)
      advance = ::TaskAdvance.find_by(id: advance_id) or return 0
      task = ::Task.find_by(id: advance.task_id) or return 0
      type = EventClassifier.classify(from: advance.from_progress, to: advance.to_progress)
      return 0 if type.nil?

      current = ::TaskAssignee.where(task_id: task.id).pluck(:person_id).map(&:to_s)
      recipients = RecipientResolver.resolve(type: type, actor_person_id: advance.by.to_s, current_assignees: current)

      insert_for(task: task, type: type, actor_id: advance.by, author_name: advance.author_name_snapshot,
                 recipients: recipients, recorded_at: advance.recorded_at,
                 n: advance.to_progress, comment: advance.comment)
    end

    # Evento de atribuição: `added` já é o delta (novos responsáveis); recipients =
    # added − autor. `recorded_at` vem da payload (fixado no enfileiramento), NÃO de
    # Time.current — senão um retry do job geraria outra chave e o índice único de
    # idempotência (1.5) não pegaria a duplicata.
    def for_assign(task_id:, added:, actor_person_id:, recorded_at: Time.current)
      task = ::Task.find_by(id: task_id) or return 0
      recipients = RecipientResolver.resolve(type: :assign, actor_person_id: actor_person_id.to_s,
                                             current_assignees: Array(added).map(&:to_s))
      actor = ::Person.find_by(id: actor_person_id)
      insert_for(task: task, type: :assign, actor_id: actor_person_id, author_name: actor&.name.to_s,
                 recipients: recipients, recorded_at: parse_time(recorded_at))
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

      Time.zone.parse(value.to_s)
    end

    # ── interno ────────────────────────────────────────────────────────────────

    def insert_for(task:, type:, actor_id:, author_name:, recipients:, recorded_at:, n: nil, comment: nil)
      return 0 if recipients.empty?

      robot = ::Robot.find_by(id: task.robot_id)
      cell = robot && ::Cell.find_by(id: robot.cell_id)
      ctx = { project_id: cell&.project_id, cell_id: robot&.cell_id, robot_id: task.robot_id, task_id: task.id }
      robot_label = robot ? "#{robot.name} - #{robot.application}" : ''

      built = MessageBuilder.build(type: type.to_s, author: author_name, task: task.desc,
                                   robot: robot_label, n: n, comment: comment)

      created = 0
      recipients.each do |recipient_id|
        created += 1 if insert_one(task, type, actor_id, recipient_id, author_name, recorded_at, built, ctx)
      end
      created
    end

    def insert_one(task, type, actor_id, recipient_id, author_name, recorded_at, built, ctx)
      # Savepoint: a violação do índice único (idempotência de assign, 1.5) rola
      # de volta SÓ este insert; a transação externa (do job) sobrevive.
      ::Notification.transaction(requires_new: true) do
        ::Notification.create!(
          workspace_id: task.workspace_id, recipient_person_id: recipient_id, actor_person_id: actor_id,
          type: type.to_s, msg: built[:msg], author_name_snapshot: author_name, format_version: built[:format_version],
          recorded_at: recorded_at, ts_local: recorded_at.strftime('%d/%m %H:%M'),
          ctx_project_id: ctx[:project_id], ctx_cell_id: ctx[:cell_id],
          ctx_robot_id: ctx[:robot_id], ctx_task_id: ctx[:task_id]
        )
      end
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end
  end
end
