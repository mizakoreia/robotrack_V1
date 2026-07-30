# frozen_string_literal: true

module Notifications
  # Compõe classifier + resolver + builder e insere as linhas (in-app-notifications
  # 4.1). Best-effort: tolera a violação do índice único de idempotência de assign
  # (1.5) SEM levantar — reexecutar com os mesmos parâmetros não cria segunda linha
  # e conclui com sucesso. Roda dentro do contexto de tenant do job.
  #
  # notification-preferences G2/G5: o caminho de avanço filtra os candidatos pelas
  # preferências do galho (SubscriptionResolver — mais-específico-vence), e o
  # caminho de atribuição notifica também o dono/seguidores em 3ª pessoa
  # (assign_observer), preservando dedup, "nunca o autor", best-effort e RLS.
  module CreateService
    module_function

    # Evento de avanço: classifica (from,to); progress/done → todos os responsáveis
    # atuais menos o autor, mais o dono (with_owner), depois filtrados pelas
    # preferências do galho (seguidores entram, silenciadores saem).
    def for_advance(advance_id:)
      advance = ::TaskAdvance.find_by(id: advance_id) or return 0
      task = ::Task.find_by(id: advance.task_id) or return 0
      type = EventClassifier.classify(from: advance.from_progress, to: advance.to_progress)
      return 0 if type.nil?

      current = ::TaskAssignee.where(task_id: task.id).pluck(:person_id).map(&:to_s)
      recipients = RecipientResolver.resolve(type: type, actor_person_id: advance.by.to_s, current_assignees: current)
      recipients = with_owner(recipients, task, advance.by)

      ctx, robot_label = ctx_for(task)
      index = SubscriptionResolver.load(ctx)
      recipients = SubscriptionResolver.filter(recipients, index, advance.by)
      return 0 if recipients.empty?

      build_args = { type: type.to_s, author: advance.author_name_snapshot, task: task.desc,
                     robot: robot_label, n: advance.to_progress, comment: advance.comment }
      insert_rows(task: task, type: type, actor_id: advance.by, author_name: advance.author_name_snapshot,
                  recipients: recipients, recorded_at: advance.recorded_at, ctx: ctx, build_args: build_args)
    end

    # Evento de atribuição: `added` é o delta (novos responsáveis). Dois grupos de
    # destinatário (D-P7):
    #   - ATRIBUÍDO (delta − autor): mensagem em 2ª pessoa ("atribuiu você").
    #     Recebe sempre — ser atribuído é evento direto, isento de `mute` (O-4).
    #   - OBSERVADOR (dono + seguidores do galho, − atribuídos − autor): mensagem em
    #     3ª pessoa ("atribuiu <fulano>"), honrando `mute`. `type` continua 'assign'
    #     (msg materializada por destinatário — SEM migração de enum).
    # `recorded_at` vem da payload (fixado no enfileiramento), NÃO de Time.current —
    # senão um retry do job geraria outra chave e o índice único de idempotência
    # (1.5) não pegaria a duplicata.
    def for_assign(task_id:, added:, actor_person_id:, recorded_at: Time.current)
      task = ::Task.find_by(id: task_id) or return 0
      added = Array(added).map(&:to_s)
      actor = actor_person_id.to_s
      when_at = parse_time(recorded_at)
      ctx, robot_label = ctx_for(task)
      actor_person = ::Person.find_by(id: actor_person_id)
      author = actor_person&.name.to_s

      created = 0

      # 2ª pessoa ao atribuído (delta − autor). Isento de mute (O-4).
      assignees = RecipientResolver.resolve(type: :assign, actor_person_id: actor, current_assignees: added)
      if assignees.any?
        build_args = { type: 'assign', author: author, task: task.desc, robot: robot_label }
        created += insert_rows(task: task, type: :assign, actor_id: actor_person_id, author_name: author,
                               recipients: assignees, recorded_at: when_at, ctx: ctx, build_args: build_args)
      end

      # 3ª pessoa aos observadores (dono + seguidores − atribuídos − autor), honrando mute.
      observers = assign_observers(task, ctx, added, actor)
      if observers.any?
        assignee_names = person_names(added)
        build_args = { type: 'assign_observer', author: author, task: task.desc,
                       robot: robot_label, assignee: assignee_names }
        created += insert_rows(task: task, type: :assign, actor_id: actor_person_id, author_name: author,
                               recipients: observers, recorded_at: when_at, ctx: ctx, build_args: build_args)
      end

      created
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

      Time.zone.parse(value.to_s)
    end

    # O DONO do workspace recebe os AVANÇOS (progress/done) de tarefas do próprio
    # workspace mesmo quando NÃO é responsável — é o "alguém editou meu workspace".
    # Regras da casa preservadas: nunca notifica o autor (owner == actor sai) e
    # deduplica (uniq) quando o dono também é responsável → uma linha só.
    # `recipients` já vem sem o autor e deduplicado.
    def with_owner(recipients, task, actor_id)
      owner_id = owner_person_id(task)
      return recipients if owner_id.nil? || owner_id == actor_id.to_s

      (recipients + [owner_id]).uniq
    end

    # Person do dono NESTE workspace (Person é WorkspaceScoped → escopo do tenant do
    # job). Dono sem Person (conta sem identidade de domínio) → nil, sem notificação.
    def owner_person_id(task)
      owner_user_id = ::Workspace.where(id: task.workspace_id).pick(:owner_user_id)
      return nil if owner_user_id.nil?

      ::Person.find_by(user_id: owner_user_id)&.id&.to_s
    end

    # Observadores de uma atribuição: dono + seguidores do galho, menos os próprios
    # atribuídos (que já recebem em 2ª pessoa) e menos o autor, honrando mute. O
    # `default` do filtro é "é o dono" — o dono recebe por padrão; um seguidor
    # não-dono entra por `follow`; qualquer um sai por `mute` no nível mais específico.
    def assign_observers(task, ctx, added, actor_id)
      index = SubscriptionResolver.load(ctx)
      owner_id = owner_person_id(task)
      defaults = [owner_id].compact - added - [actor_id]
      universe = (defaults + SubscriptionResolver.followers(index)).uniq - added - [actor_id]
      universe.select { |pid| SubscriptionResolver.wants?(pid, index, default: defaults.include?(pid)) }
    end

    def person_names(ids)
      return '' if ids.empty?

      by_id = ::Person.where(id: ids).pluck(:id, :name).to_h { |id, name| [id.to_s, name] }
      names = ids.map { |id| by_id[id.to_s] }.compact
      names.length <= 1 ? names.first.to_s : "#{names[0..-2].join(', ')} e #{names[-1]}"
    end

    # ── interno ────────────────────────────────────────────────────────────────

    # ctx desnormalizado (4 colunas, não jsonb — D-N2) subindo task→robot→cell, e o
    # rótulo do robô para a mensagem.
    def ctx_for(task)
      robot = ::Robot.find_by(id: task.robot_id)
      cell = robot && ::Cell.find_by(id: robot.cell_id)
      ctx = { project_id: cell&.project_id, cell_id: robot&.cell_id, robot_id: task.robot_id, task_id: task.id }
      robot_label = robot ? "#{robot.name} - #{robot.application}" : ''
      [ctx, robot_label]
    end

    # internationalization G6 (D-I5a) — a msg é CONGELADA no locale de CADA
    # destinatário. Constrói uma vez por locale distinto (cache) e insere a linha
    # daquele destinatário com o texto do idioma dele. A idempotência/savepoint por
    # linha do `insert_one` seguem intactos.
    def insert_rows(task:, type:, actor_id:, author_name:, recipients:, recorded_at:, ctx:, build_args:)
      locales = recipient_locales(recipients)
      cache = {}
      created = 0
      recipients.each do |recipient_id|
        loc = locales[recipient_id.to_s] || MessageBuilder::LOCALE
        built = (cache[loc] ||= MessageBuilder.build(**build_args, locale: loc))
        created += 1 if insert_one(task, type, actor_id, recipient_id, author_name, recorded_at, built, ctx)
      end
      created
    end

    # Locale de cada destinatário: Person → user_id → User.locale. Pessoa sem conta
    # (snapshot histórico) ou sem locale → nil (o chamador aplica o default pt-BR).
    def recipient_locales(ids)
      return {} if ids.empty?

      people = ::Person.where(id: ids).pluck(:id, :user_id)
      user_locales = ::User.where(id: people.map(&:last).compact).pluck(:id, :locale).to_h
      people.to_h { |pid, uid| [pid.to_s, uid && user_locales[uid]] }
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
