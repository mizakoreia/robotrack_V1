# frozen_string_literal: true

# `class AuditLog` (namespace explícito do model).
class AuditLog
  # audit-log 3.3/3.4 (§2.8, Decisão 3/4/5/6) — o ÚNICO produtor de linhas de
  # auditoria. Chamado de DENTRO de uma transação já aberta (a do avanço, G3; a do
  # reset, workspace-settings) — se o INSERT falhar, `record!` levanta e a transação
  # envolvente faz rollback (log transacional, Decisão 3: avanço sem log não commita).
  #
  # Renderiza `msg` (format string versionada do locale, Decisão 5) e `ts_local`
  # (fuso do workspace) NO MOMENTO da escrita e os CONGELA na linha (Decisão 4). Não
  # faz dedup próprio: a idempotência vem da PK do avanço (D1/Decisão 3).
  module RecordService
    module_function

    # workspace: o Workspace (RLS exige workspace_id = contexto corrente).
    # event:   :task_completed | :workspace_reset.
    # by:      a Person que agiu (nil para importação legada — by_name vem do payload).
    # payload: dados do evento; para task_completed: robot/task/assignee_names;
    #          para workspace_reset: projects_count. Guardado em jsonb (Decisão 4).
    def record!(workspace:, event:, by:, payload:, now: Time.current,
                time_zone: Reports::DocumentId::DEFAULT_TIME_ZONE)
      event = event.to_s
      raise ArgumentError, "evento de auditoria inválido: #{event}" unless EVENT_TYPES.include?(event)

      version   = FORMAT_VERSIONS.fetch(event)
      by_name   = (by&.name.presence || payload[:by_name].presence)
      rendered  = render_msg(event, version, by_name, payload)
      ts_local  = render_ts_local(now, time_zone)

      AuditLog.create!(
        id: payload[:id].presence, workspace_id: workspace.id,
        event_type: event, format_version: version,
        msg: rendered, ts: now, ts_local: ts_local,
        by_person_id: by&.id, by_name: by_name,
        payload: machine_payload(payload)
      )
    end

    # ---- render (congelado no INSERT) ----

    def render_msg(event, version, by_name, payload)
      I18n.t(
        "audit.#{event}.v#{version}",
        robot: payload[:robot_name], task: payload[:task_desc],
        assignees: Array(payload[:assignee_names]).join(', '),
        by_name: by_name, projects_count: payload[:projects_count]
      )
    end

    # ts_local no fuso do workspace (Decisão 4; default America/Sao_Paulo — reuso do
    # DocumentId). Formatação estável, independente do fuso do navegador de quem lê.
    def render_ts_local(now, time_zone)
      zone = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone[Reports::DocumentId::DEFAULT_TIME_ZONE]
      now.in_time_zone(zone).strftime('%d/%m/%Y %H:%M')
    end

    # Só os campos de DADO (leitura por máquina) — sem :id (é coluna) nem :by_name.
    def machine_payload(payload)
      payload.except(:id, :by_name).transform_keys(&:to_s)
    end
  end
end
