# frozen_string_literal: true

module TaskAdvances
  # progress-advances 3.1–3.5 (§2.4, D-ID, D-409, D-TS, D-AUTO, D6) — a transação
  # completa do registro de avanço, a ÚNICA porta de escrita de `tasks.progress`.
  #
  # Ordem (D-ID — idempotência ANTES do lock_version, senão um retry de sucesso
  # veria versão velha e responderia 409 falso):
  #   1. avanço com este uuid já existe? → 200 com o avanço e a tarefa atual
  #      (não recria, não reaplica, não re-notifica).
  #   2. tarefa invisível (inexistente/soft-deleted/alheia) → 404.
  #   3. `lock_version` divergente do enviado → 409 com o estado atual (D-409).
  #   4. resolve a transição (ApplyTransitionService), clampa `recorded_at` (D-TS),
  #      e numa transação: cria a entrada, muta `tasks` (status+progress,
  #      `lock_version` incrementa sozinho), auto-atribui o autor se a tarefa não
  #      tem responsável (D-AUTO), grava auditoria se chegou a 100.
  #   5. pós-commit best-effort: evento `task.advanced` (D6). Falha não derruba o
  #      save.
  class CreateService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(task_id:, id:, progress: nil, status: nil, comment: nil, recorded_at: nil, lock_version: nil)
      person = @context&.person
      return error_response('sem_pessoa_do_ator', 422) if person.nil?

      replay = id.present? ? ::TaskAdvance.find_by(id: id) : nil
      if replay
        task = ::Task.find_by(id: replay.task_id)
        return success_response({ advance: replay, task: task, replay: true }, 200)
      end

      task = ::Task.find_by(id: task_id)
      return error_response('not_found', 404) if task.nil?

      if lock_version && task.lock_version != lock_version.to_i
        return error_response('conflito_de_versao', 409, details: conflict_body(task))
      end

      resolved = ::Tasks::ApplyTransitionService.resolve(
        current_status: task.status, current_progress: task.progress, progress: progress, status: status
      )
      ra, adjusted = clamp_recorded_at(recorded_at)

      advance = nil
      # `requires_new: true` — o request já roda dentro de UMA transação (o
      # middleware de tenant abre uma, e `Tenant.with` também nos testes). Sem o
      # SAVEPOINT, um `StaleObjectError` marcaria só a transação interna e o
      # `advance.create!` seguiria pendente na externa, que commitaria: o 409
      # persistiria o avanço. Com savepoint, o rollback desfaz a entrada.
      ActiveRecord::Base.transaction(requires_new: true) do
        advance = ::TaskAdvance.create!(
          id: id.presence, task_id: task.id, by: person.id, author_name_snapshot: person.name,
          from_progress: task.progress, to_progress: resolved.progress,
          comment: comment, legacy: false, recorded_at: ra, recorded_at_adjusted: adjusted
        )
        task.update!(status: resolved.status, progress: resolved.progress)
        auto_assign!(task, person)
        audit_completion!(task, advance, person) if resolved.completed
      end

      publish_event(task, advance)
      success_response({ advance: advance, task: task.reload, replay: false }, 201)
    rescue ActiveRecord::StaleObjectError
      error_response('conflito_de_versao', 409, details: conflict_body(task.reload))
    rescue ActiveRecord::RecordInvalid => e
      error_response('validation_error', 422, details: e.record.errors.messages)
    rescue ActiveRecord::RecordNotUnique
      # colisão de uuid (retry cross-workspace, astronômico) — trata como conflito.
      error_response('conflito_de_versao', 409)
    end

    private

    SKEW_MINUTES = ENV.fetch('ADVANCE_RECORDED_AT_SKEW_MINUTES', '10').to_i
    MAX_PAST_DAYS = 90

    # D-TS — ausente → now(); futuro além do skew ou passado além de 90 dias →
    # clamp para agora (≈created_at), com `recorded_at_adjusted = true`. Rejeitar
    # perderia o avanço de um tablet com relógio errado.
    def clamp_recorded_at(recorded_at)
      now = Time.current
      ra = parse_time(recorded_at)
      return [now, false] if ra.nil?
      return [now, true] if ra > now + SKEW_MINUTES.minutes || ra < now - MAX_PAST_DAYS.days

      [ra, false]
    end

    def parse_time(value)
      return nil if value.nil?
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    # D-AUTO — auto-atribui o autor SÓ se a tarefa não tem nenhum responsável. O
    # índice único `(task_id, person_id)` (robot-tasks) barra a corrida.
    def auto_assign!(task, person)
      return if ::TaskAssignee.where(task_id: task.id).exists?

      ::TaskAssignee.create!(task_id: task.id, person_id: person.id, workspace_id: task.workspace_id)
    end

    # Conclusão a 100% grava auditoria na MESMA transação. `audit_logs` (audit-log)
    # ainda não existe — por ora, log estruturado, mesmo padrão de
    # `Hierarchy::CrudService#audit_destroy!` (EXECUCAO decisão 2).
    def audit_completion!(task, advance, person)
      Rails.logger.info(
        {
          event: 'task_completed', task_id: task.id, robot_id: task.robot_id,
          workspace_id: task.workspace_id, by_person_id: person.id,
          author: person.name, advance_id: advance.id, at: advance.recorded_at
        }.to_json
      )
    end

    # D6 — evento pós-commit best-effort. `WorkspaceChannel` (Cable) é de
    # realtime-collaboration; aqui só a notificação, que falha para o rastreio,
    # nunca para a resposta.
    def publish_event(task, advance)
      ActiveSupport::Notifications.instrument(
        'task.advanced',
        task_id: task.id, robot_id: task.robot_id, workspace_id: task.workspace_id,
        advance_id: advance.id, to_progress: advance.to_progress, status: task.status
      )
    rescue StandardError => e
      Rails.logger.error({ event: 'task_advanced_publish_failed', error: e.message }.to_json)
    end

    def conflict_body(task)
      latest = ::TaskAdvance.where(task_id: task.id).order(recorded_at: :desc, created_at: :desc, id: :desc).first
      {
        task: { id: task.id, progress: task.progress, status: task.status, lock_version: task.lock_version },
        latest_advance: latest && {
          author_name_snapshot: latest.author_name_snapshot, to_progress: latest.to_progress,
          recorded_at: latest.recorded_at, comment: latest.comment
        }
      }.compact
    end
  end
end
