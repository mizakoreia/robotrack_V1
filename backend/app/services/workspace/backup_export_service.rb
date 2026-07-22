# frozen_string_literal: true

require 'digest'
require 'json'

class Workspace
  # workspace-settings 4.2 (§3.11, D-EXP) — o export do estado completo do workspace
  # como `RoboTrack_Database.json`: esqueleto aninhado (workspace → projetos →
  # células → robôs → tarefas) + coleções de topo (people/memberships/invitations/
  # notifications/auditLogs/taskTemplates) + o envelope `_rt`.
  #
  # LOSSLESS na direção nativa: cada tarefa carrega `assignees` (nomes, o legado lê)
  # E `assigneeIds` (uuid, nosso importador prefere), e `advances` (estruturado, D8).
  # `_rt.checksum` é o sha256 do payload SEM `_rt`, com chaves ordenadas — dois
  # exports do mesmo estado dão o MESMO checksum (só `exportedAt` varia). É o contrato
  # congelado em `spec/fixtures/backup/roboTrack_database_v2.json` (D-EXP); qualquer
  # campo novo em qualquer capacidade downstream muda o checksum e o round-trip pega.
  #
  # Escopo `owner` (carrega e-mails) — a autorização é do endpoint (D-EXP-ROLE). Roda
  # em contexto de tenant (RLS escopa tudo ao workspace).
  class BackupExportService
    SCHEMA_VERSION = 2

    def self.call(workspace:, now: Time.current)
      new(workspace).call(now: now)
    end

    def initialize(workspace)
      @ws = workspace
    end

    def call(now: Time.current)
      payload  = build_payload
      checksum = Digest::SHA256.hexdigest(canonical(payload))
      counts   = build_counts(payload)
      full = payload.merge(
        '_rt' => {
          'schemaVersion' => SCHEMA_VERSION,
          'exportedAt' => now.utc.iso8601,
          'workspaceId' => @ws.id,
          'counts' => counts,
          'checksum' => checksum
        }
      )
      { json: JSON.pretty_generate(deep_sort(full)), checksum: checksum, counts: counts }
    end

    private

    def build_payload
      {
        'workspace' => { 'id' => @ws.id, 'name' => @ws.name },
        'projects' => build_tree,
        'people' => ::Person.order(:id).map { |p| person_row(p) },
        'memberships' => ::Membership.order(:id).map { |m| membership_row(m) },
        'invitations' => ::Invitation.order(:id).map { |i| invitation_row(i) },
        'taskTemplates' => ::TaskTemplate.order(:id).map { |t| template_row(t) },
        'auditLogs' => ::AuditLog.order(:ts, :id).map { |a| audit_row(a) },
        # in-app-notifications ainda não existe → coleção reservada, vazia.
        'notifications' => []
      }
    end

    def build_tree
      cells   = ::Cell.order(:position, :id).group_by(&:project_id)
      robots  = ::Robot.order(:position, :id).group_by(&:cell_id)
      tasks   = ::Task.where(deleted_at: nil).order(:position, :id).group_by(&:robot_id)
      assign  = assignees_by_task
      adv     = ::TaskAdvance.order(:recorded_at, :id).group_by(&:task_id)

      ::Project.order(:position, :id).map do |p|
        {
          'id' => p.id, 'name' => p.name, 'position' => p.position,
          'cells' => (cells[p.id] || []).map do |c|
            {
              'id' => c.id, 'name' => c.name, 'position' => c.position,
              'robots' => (robots[c.id] || []).map do |r|
                {
                  'id' => r.id, 'name' => r.name, 'application' => r.application, 'position' => r.position,
                  'tasks' => (tasks[r.id] || []).map { |t| task_row(t, assign[t.id] || { names: [], ids: [] }, adv[t.id] || []) }
                }
              end
            }
          end
        }
      end
    end

    def assignees_by_task
      rows = ::TaskAssignee.joins('JOIN people ON people.id = task_assignees.person_id')
                           .pluck(:task_id, :person_id, 'people.name')
      rows.group_by { |r| r[0] }.transform_values do |list|
        sorted = list.sort_by { |r| r[2].to_s }
        { names: sorted.map { |r| r[2] }, ids: sorted.map { |r| r[1] } }
      end
    end

    def task_row(t, assign, advances)
      {
        'id' => t.id, 'cat' => t.cat, 'desc' => t[:desc], 'weight' => numeric(t.weight),
        'progress' => t.progress, 'status' => t.status, 'position' => t.position,
        'assignees' => assign[:names], 'assigneeIds' => assign[:ids],
        'advances' => advances.map { |a| advance_row(a) }
      }
    end

    def advance_row(a)
      {
        'id' => a.id, 'from' => a.from_progress, 'to' => a.to_progress,
        'comment' => a.comment, 'author' => a.author_name_snapshot, 'legacy' => a.legacy,
        'recordedAt' => a.recorded_at&.utc&.iso8601, 'createdAt' => a.created_at&.utc&.iso8601
      }
    end

    def person_row(p)
      { 'id' => p.id, 'name' => p.name, 'email' => p.email, 'userId' => p.user_id, 'archivedAt' => p.archived_at&.utc&.iso8601 }
    end

    def membership_row(m)
      { 'id' => m.id, 'userId' => m.user_id, 'personId' => m.person_id, 'role' => m.role, 'invitationId' => m.invitation_id }
    end

    def invitation_row(i)
      { 'id' => i.id, 'email' => i.email, 'role' => i.role, 'createdByPersonId' => i.created_by_person_id,
        'expiresAt' => i.expires_at&.utc&.iso8601, 'usedAt' => i.used_at&.utc&.iso8601 }
    end

    def template_row(t)
      { 'id' => t.id, 'cat' => t.cat, 'desc' => t[:desc], 'weight' => numeric(t.weight), 'appFilters' => Array(t.app_filters).sort }
    end

    def audit_row(a)
      { 'id' => a.id, 'eventType' => a.event_type, 'formatVersion' => a.format_version, 'msg' => a.msg,
        'ts' => a.ts&.utc&.iso8601, 'tsLocal' => a.ts_local, 'byName' => a.by_name, 'byPersonId' => a.by_person_id,
        'payload' => a.payload }
    end

    def build_counts(payload)
      robots = payload['projects'].sum { |p| p['cells'].sum { |c| c['robots'].size } }
      tasks  = payload['projects'].sum { |p| p['cells'].sum { |c| c['robots'].sum { |r| r['tasks'].size } } }
      {
        'projects' => payload['projects'].size,
        'cells' => payload['projects'].sum { |p| p['cells'].size },
        'robots' => robots, 'tasks' => tasks,
        'people' => payload['people'].size, 'auditLogs' => payload['auditLogs'].size,
        'taskTemplates' => payload['taskTemplates'].size
      }
    end

    # numeric integral (1.0 → 1) para o export não divergir por formatação.
    def numeric(v) = v == v.to_i ? v.to_i : v.to_f

    # sha256 sobre a serialização canônica (chaves ordenadas) do payload SEM `_rt`.
    def canonical(payload) = JSON.generate(deep_sort(payload))

    def deep_sort(node)
      case node
      when Hash  then node.keys.sort.to_h { |k| [k, deep_sort(node[k])] }
      when Array then node.map { |e| deep_sort(e) }
      else node
      end
    end
  end
end
