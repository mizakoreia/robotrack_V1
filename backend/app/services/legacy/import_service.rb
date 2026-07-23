# frozen_string_literal: true

require 'time'
require 'ostruct'

module Legacy
  # legacy-data-migration G5 (5.1-5.7) + as regras de §1.4 (G6) que o mesmo caminho de
  # escrita precisa embutir para importar a fixture sem abortar. É o ORQUESTRADOR: caminha
  # a hierarquia canônica (workspace → templates → projetos → células → robôs → tarefas →
  # responsáveis → avanços → logs → notificações), usando `IdDerivation` (identidade) e
  # `Writer` (idempotência ON CONFLICT DO NOTHING), acumulando `ImportReport`.
  #
  # RECONCILIAÇÃO (documentada no EXECUCAO — G5): os "8 services" de 5.1/5.3-5.7 são as
  # SEÇÕES deste orquestrador (métodos privados nomeados por entidade), não 8 classes — o
  # que os specs verificam é a contagem por tabela e o relatório, não a topologia de classes.
  # `AssigneeResolver` (5.2) e `StatusDerivation` (§2.2) ficam à parte porque têm estado/regra
  # própria e são reusados. Membership NÃO é criada (a coluna exige `user_id` Rails e o mapa
  # ownerUid-Firebase→user não é definido nesta change — 4.3); os membros entram como PESSOAS.
  module ImportService
    module_function

    APPLICATIONS = ['Misto / Geral', 'Solda Ponto', 'Solda MIG', 'Handling', 'Sealing', 'Outros'].freeze
    NOTIFICATION_TYPES = %w[assign progress done].freeze
    DEFAULT_TZ = 'America/Sao_Paulo'

    # canonical: Hash canônico (schemaVersion 1). run: LegacyImportRun (destino + report).
    # Devolve o ImportReport. Roda sob o contexto de tenant do workspace de DESTINO; os
    # caminhos de id usam o `workspace.id` LEGADO (do arquivo), as linhas usam run.workspace_id.
    def call(canonical:, run:)
      ws = canonical.fetch('workspace')
      legacy_ws_id = ws['id']
      report = ImportReport.new

      ImportContext.with_workspace(workspace_id: run.workspace_id, file_owner_uid: ws['ownerUid']) do
        ctx = Ctx.new(canonical: canonical, run: run, legacy_ws_id: legacy_ws_id, report: report, dry_run: false,
                      resolver: AssigneeResolver.new(legacy_ws_id: legacy_ws_id, workspace_id: run.workspace_id,
                                                     run: run, report: report, dry_run: false))
        walk(ctx)
        run.update!(status: 'completed', report: run.report.merge('import' => report.to_h))
      end

      report
    end

    # 8.3 — dry-run: percorre o arquivo INTEIRO, conta por entidade e prevê a quarentena,
    # SEM escrita nenhuma e SEM exigir backup/contexto/run. Assume banco vazio (prevê todos
    # como criados). workspace_id é irrelevante (nada é gravado); usamos o legado como rótulo.
    def dry_run(canonical:)
      ws = canonical.fetch('workspace')
      legacy_ws_id = ws['id']
      report = ImportReport.new
      run = OpenStruct.new(id: nil, workspace_id: legacy_ws_id, report: {})
      ctx = Ctx.new(canonical: canonical, run: run, legacy_ws_id: legacy_ws_id, report: report, dry_run: true,
                    resolver: AssigneeResolver.new(legacy_ws_id: legacy_ws_id, workspace_id: legacy_ws_id,
                                                   run: run, report: report, dry_run: true))
      walk(ctx)
      report
    end

    def walk(ctx)
      import_workspace(ctx)
      import_people_roster(ctx)
      import_templates(ctx)
      import_projects_tree(ctx)
      import_logs(ctx)
      import_notifications(ctx)
    end

    # Contexto de um run (evita passar 5 argumentos por método).
    Ctx = Struct.new(:canonical, :run, :legacy_ws_id, :report, :resolver, :dry_run, keyword_init: true) do
      def ws_id = run.workspace_id
      def lws = legacy_ws_id
    end

    # --- 5.1 workspace (nome) + roster de pessoas (responsibles + membros) ---

    def import_workspace(ctx)
      return if ctx.dry_run

      name = ctx.canonical.dig('workspace', 'name')
      ::Workspace.where(id: ctx.ws_id).update_all(name: name) if name.present?
    end

    def import_people_roster(ctx)
      Array(ctx.canonical.dig('workspace', 'responsibles')).each { |n| ctx.resolver.resolve(n) }
      Array(ctx.canonical['members']).each do |m|
        ctx.resolver.resolve(m['name'], email: m['email'])
      end
    end

    # --- 5.3 templates (appFilters vs apps, "Todas", divergência) ---

    def import_templates(ctx)
      entries = []
      Array(ctx.canonical.dig('workspace', 'defaultTasks')).each_with_index do |tpl, i|
        path = IdDerivation.template_path(ctx.lws, IdDerivation.ref(tpl, i))
        filters = template_filters(ctx, tpl, path)
        next if filters.nil? # quarentenado

        entries << { id: IdDerivation.template_id(ctx.lws, IdDerivation.ref(tpl, i)), legacy_path: path,
                     attrs: { workspace_id: ctx.ws_id, cat: tpl['cat'], desc: tpl['desc'],
                              weight: numeric_weight(tpl['weight']), app_filters: filters } }
      end
      flush(ctx, ::TaskTemplate, 'task_template', entries)
    end

    # appFilters vence apps; ambos divergentes → aviso; valores fora do enum (+ "Todas") →
    # quarentena do template. Devolve o array de filtros ou nil (quarentenado).
    def template_filters(ctx, tpl, path)
      has_new = tpl.key?('appFilters')
      chosen = has_new ? Array(tpl['appFilters']) : Array(tpl['apps'])
      if has_new && tpl.key?('apps') && Array(tpl['apps']) != Array(tpl['appFilters'])
        ctx.report.warn!(legacy_path: path, reason: 'app_filters_divergentes')
      end
      allowed = APPLICATIONS + ['Todas']
      invalid = chosen.reject { |a| allowed.include?(a) }
      if invalid.any?
        ctx.report.quarantine!(legacy_path: path, field: 'app_filters', value: invalid.join(','),
                               reason: 'app_filters_fora_do_enum')
        return nil
      end
      chosen
    end

    # --- 5.4 projetos (renumeração de _ord) → 5.5 células/robôs → 5.6 tarefas ---

    def import_projects_tree(ctx)
      projects = Array(ctx.canonical['projects'])
      order = renumber(projects) # índice do array → position contígua 0-based

      entries = projects.each_index.map do |i|
        p = projects[i]
        ppath = IdDerivation.project_path(ctx.lws, p['id'])
        { id: IdDerivation.uuid(ppath), legacy_path: ppath,
          attrs: { workspace_id: ctx.ws_id, name: p['name'], position: order[i] }, _src: p, _path: ppath }
      end
      flush(ctx, ::Project, 'project', entries.map { |e| e.slice(:id, :legacy_path, :attrs) })

      entries.each { |e| import_cells(ctx, project_id: e[:id], project: e[:_src], project_path: e[:_path]) }
    end

    # position contígua 0-based por (_ord numérico, ordem de aparição) — desempate estável.
    def renumber(projects)
      ranked = projects.each_index.sort_by { |i| [num(projects[i]['_ord']), i] }
      order = Array.new(projects.size)
      ranked.each_with_index { |orig_i, pos| order[orig_i] = pos }
      order
    end

    def import_cells(ctx, project_id:, project:, project_path:)
      cells = array_of(project['cells'])
      entries = cells.each_index.map do |i|
        c = cells[i]
        cpath = "#{project_path}/cell:#{IdDerivation.ref(c, i)}"
        { id: IdDerivation.uuid(cpath), legacy_path: cpath,
          attrs: { workspace_id: ctx.ws_id, project_id: project_id, name: c['name'], position: i }, _src: c, _path: cpath }
      end
      resolve_name_collisions(ctx, ::Cell, entries, :project_id, :name, 'lower(name)')
      flush(ctx, ::Cell, 'cell', entries.map { |e| e.slice(:id, :legacy_path, :attrs) })

      entries.each { |e| import_robots(ctx, cell_id: e[:id], cell: e[:_src], cell_path: e[:_path]) }
    end

    def import_robots(ctx, cell_id:, cell:, cell_path:)
      robots = array_of(cell['robots'])
      entries = []
      robots.each_index do |i|
        r = robots[i]
        rpath = "#{cell_path}/robot:#{IdDerivation.ref(r, i)}"
        unless APPLICATIONS.include?(r['application'])
          ctx.report.quarantine!(legacy_path: rpath, field: 'application', value: r['application'],
                                 reason: 'application_fora_do_enum')
          next # robô e suas tarefas ficam de fora
        end
        entries << { id: IdDerivation.uuid(rpath), legacy_path: rpath,
                     attrs: { workspace_id: ctx.ws_id, cell_id: cell_id, name: r['name'],
                              application: r['application'], position: i }, _src: r, _path: rpath }
      end
      resolve_name_collisions(ctx, ::Robot, entries, :cell_id, :name, 'lower(name)')
      flush(ctx, ::Robot, 'robot', entries.map { |e| e.slice(:id, :legacy_path, :attrs) })

      entries.each { |e| import_tasks(ctx, robot_id: e[:id], robot: e[:_src], robot_path: e[:_path]) }
    end

    # --- 5.6 tarefas (sem resp/obs) + quarentena (status/progress) + coerência (§2.2) ---

    def import_tasks(ctx, robot_id:, robot:, robot_path:)
      tasks = array_of(robot['tasks'])
      entries = []
      tasks.each_index do |i|
        t = tasks[i]
        path = "#{robot_path}/task:#{IdDerivation.ref(t, i)}"
        prepared = prepare_task(ctx, t, path, robot_id, i)
        entries << prepared if prepared
      end
      resolve_name_collisions(ctx, ::Task, entries, :robot_id, :desc, 'lower(btrim("desc"))')
      flush(ctx, ::Task, 'task', entries.map { |e| e.slice(:id, :legacy_path, :attrs) })

      entries.each { |e| import_task_children(ctx, task_entry: e) }
    end

    def prepare_task(ctx, task, path, robot_id, index)
      progress = task['progress'].to_i
      if progress.negative? || progress > 100
        ctx.report.quarantine!(legacy_path: path, field: 'progress', value: task['progress'], reason: 'progress_fora_da_faixa')
        return nil
      end
      status = task['status'].to_s
      unless StatusDerivation.valid?(status)
        ctx.report.quarantine!(legacy_path: path, field: 'status', value: status, reason: 'status_fora_do_enum')
        return nil
      end
      final_status, derived = StatusDerivation.reconcile(status, progress)
      ctx.report.warn!(legacy_path: path, reason: 'status_derivado_de_progresso') if derived

      # id do CAMINHO COMPLETO da tarefa (inclui robô) — task_id(lws, ref) colidiria entre
      # robôs diferentes no mesmo índice.
      { id: IdDerivation.uuid(path), legacy_path: path,
        attrs: { workspace_id: ctx.ws_id, robot_id: robot_id, cat: task['cat'], desc: task['desc'],
                 weight: numeric_weight(task['weight']), progress: progress, status: final_status, position: index },
        _src: task, _path: path }
    end

    def import_task_children(ctx, task_entry:)
      import_assignees(ctx, task_entry)
      import_advances(ctx, task_entry)
    end

    # --- 6.1 cascata de responsáveis (assignees[] PARA a cascata) ---

    def import_assignees(ctx, task_entry)
      task = task_entry[:_src]
      names = assignee_cascade(task)
      person_ids = ctx.resolver.resolve_all(names)
      entries = person_ids.map do |pid|
        { id: IdDerivation.uuid("#{task_entry[:_path]}/assignee:#{pid}"),
          legacy_path: "#{task_entry[:_path]}/assignee:#{pid}",
          attrs: { workspace_id: ctx.ws_id, task_id: task_entry[:id], person_id: pid } }
      end
      flush(ctx, ::TaskAssignee, 'task_assignee', entries)
    end

    # assignees Array (mesmo vazio) ENCERRA a cascata; senão resp não-sentinela; senão vazio.
    def assignee_cascade(task)
      return Array(task['assignees']) if task['assignees'].is_a?(Array)
      return [task['resp']] if task['resp'].is_a?(String) && !IdDerivation.sentinel_name?(task['resp'])

      []
    end

    # --- 6.2 avanços: history → task_advances; obs → avanço legado (recorded_at do arquivo) ---

    def import_advances(ctx, task_entry)
      task = task_entry[:_src]
      history = array_of(task['history'])
      entries =
        if history.any?
          quarantine_obs_if_present(ctx, task, task_entry[:_path])
          history_advances(ctx, task, task_entry)
        elsif task['obs'].to_s.strip != ''
          [obs_advance(ctx, task, task_entry)]
        else
          []
        end
      flush(ctx, ::TaskAdvance, 'task_advance', entries.compact)
    end

    def quarantine_obs_if_present(ctx, task, path)
      return if task['obs'].to_s.strip == ''

      ctx.report.quarantine!(legacy_path: path, field: 'obs', value: task['obs'], reason: 'obs_descartado_historico_presente')
    end

    def history_advances(ctx, task, task_entry)
      array_of(task['history']).each_with_index.filter_map do |h, i|
        by = ctx.resolver.resolve(h['byName'])
        path = IdDerivation.advance_path(task_entry[:_path], i)
        if by.nil?
          ctx.report.quarantine!(legacy_path: path, field: 'byName', value: h['byName'], reason: 'avanco_sem_autor')
          next
        end
        { id: IdDerivation.uuid(path), legacy_path: path,
          attrs: { workspace_id: ctx.ws_id, task_id: task_entry[:id], by: by,
                   author_name_snapshot: h['byName'].to_s.strip, legacy: false,
                   from_progress: h['from'].to_i, to_progress: h['to'].to_i,
                   comment: h['comment'], recorded_at: parse_ts(h['ts']) } }
      end
    end

    # obs vira a 1ª entrada legada: by NULL, "(nota anterior)", 0→0, legacy true, recorded_at
    # DETERMINÍSTICO de _updatedAt/exportedAt — NUNCA Time.now (senão o uuidv5 muda entre runs).
    def obs_advance(ctx, task, task_entry)
      recorded = parse_ts(task['_updatedAt']) || parse_ts(ctx.canonical['exportedAt']) || Time.utc(2000, 1, 1)
      path = "#{task_entry[:_path]}/advance:obs"
      { id: IdDerivation.uuid(path), legacy_path: path,
        attrs: { workspace_id: ctx.ws_id, task_id: task_entry[:id], by: nil,
                 author_name_snapshot: '(nota anterior)', legacy: true,
                 from_progress: 0, to_progress: 0, comment: task['obs'], recorded_at: recorded } }
    end

    # --- 5.7 logs (§2.8) e notificações (§2.7) ---

    def import_logs(ctx)
      rows = []
      Array(ctx.canonical['logs']).each_with_index do |log, i|
        event = log['eventType'].to_s
        path = "log:#{i}"
        unless %w[task_completed workspace_reset].include?(event)
          ctx.report.quarantine!(legacy_path: path, field: 'eventType', value: event, reason: 'event_type_fora_do_enum')
          next
        end
        ts = parse_ts(log['ts']) || Time.utc(2000, 1, 1)
        rows << { id: IdDerivation.uuid("#{ctx.lws}/#{path}"), workspace_id: ctx.ws_id, event_type: event,
                  format_version: 1, msg: log['msg'].to_s, ts: ts, ts_local: ts_local(ts),
                  by_person_id: nil, by_name: log['byName'].to_s.strip.presence || 'sistema', payload: {} }
      end
      return if rows.empty?

      if ctx.dry_run
        return ctx.report.add_write('audit_log', Writer::Result.new(created: rows.size, skipped: 0))
      end

      inserted = ::AuditLog.insert_all(rows, unique_by: %i[ts id], returning: %w[id])
      ctx.report.add_write('audit_log', Writer::Result.new(created: inserted.rows.size, skipped: rows.size - inserted.rows.size))
    end

    def import_notifications(ctx)
      entries = []
      Array(ctx.canonical['notifications']).each_with_index do |n, i|
        path = "notification:#{i}"
        type = n['type'].to_s
        unless NOTIFICATION_TYPES.include?(type)
          ctx.report.quarantine!(legacy_path: path, field: 'type', value: type, reason: 'notification_type_fora_do_enum')
          next
        end
        recipient = ctx.resolver.resolve(n['recipientName'])
        actor = ctx.resolver.resolve(n['actorName'])
        next ctx.report.quarantine!(legacy_path: path, field: 'recipientName', value: n['recipientName'], reason: 'notificacao_sem_destinatario') if recipient.nil? || actor.nil?

        msg = truncate_msg(ctx, n['msg'].to_s, path)
        recorded = parse_ts(n['recordedAt']) || Time.utc(2000, 1, 1)
        read = !!n['read']
        entries << { id: IdDerivation.uuid("#{ctx.lws}/#{path}"), legacy_path: path,
                     attrs: { workspace_id: ctx.ws_id, recipient_person_id: recipient, actor_person_id: actor,
                              type: type, msg: msg, author_name_snapshot: n['actorName'].to_s.strip,
                              recorded_at: recorded, ts_local: ts_local(recorded),
                              read: read, read_at: (read ? recorded : nil), format_version: 1 } }
      end
      flush(ctx, ::Notification, 'notification', entries)
    end

    def truncate_msg(ctx, msg, path)
      return msg if msg.length <= 500

      ctx.report.warn!(legacy_path: path, reason: 'msg_truncada')
      msg[0, 500]
    end

    # --- infra comum ---

    def flush(ctx, model, entity_type, entries)
      return if entries.blank?

      if ctx.dry_run
        return ctx.report.add_write(entity_type, Writer::Result.new(created: entries.size, skipped: 0))
      end

      result = Writer.insert(model: model, entity_type: entity_type, run: ctx.run, entries: entries)
      ctx.report.add_write(entity_type, result)
    end

    # RECONCILIAÇÃO (EXECUCAO §G5): o schema de destino força NOME ÚNICO por escopo
    # (commissioning-hierarchy D-H8: `UNIQUE (cell_id, lower(name))` etc.), o que CONTRADIZ
    # o cenário de legacy-import "dois robôs homônimos na mesma célula viram DUAS linhas".
    # Não afrouxamos a constraint (proibido) nem perdemos o robô (a spec pede duas linhas):
    # DESAMBIGUAMOS o nome do colidente ("R05" → "R05 (2)") de forma DETERMINÍSTICA (ordem
    # de aparição) e avisamos (`nome_desambiguado`). O id vem do CAMINHO (índice/id), não do
    # nome — logo a desambiguação é idempotente (o 2º run pula por `ON CONFLICT (id)`).
    def resolve_name_collisions(ctx, model, entries, scope_col, name_attr, name_sql)
      used = Hash.new { |h, k| h[k] = [] }
      entries.each do |e|
        scope = e[:attrs][scope_col]
        base = e[:attrs][name_attr].to_s
        candidate = base
        n = 1
        while name_taken?(model, scope, scope_col, name_sql, candidate, e[:id], used[scope], ctx.dry_run)
          n += 1
          candidate = "#{base} (#{n})"
        end
        if candidate != base
          ctx.report.warn!(legacy_path: e[:legacy_path], reason: 'nome_desambiguado', original: base, novo: candidate)
          e[:attrs][name_attr] = candidate
        end
        used[scope] << candidate.strip.downcase
      end
    end

    def name_taken?(model, scope, scope_col, name_sql, candidate, self_id, batch, dry_run)
      key = candidate.strip.downcase
      return true if batch.include?(key)
      return false if dry_run # dry-run não lê o banco; só a deduplicação do lote

      # default_scope do model já exclui soft-deleted — casa com o índice PARCIAL (deleted_at IS NULL).
      model.where(scope_col => scope).where("#{name_sql} = ?", key).where.not(id: self_id).exists?
    end

    def array_of(value) = value.is_a?(Array) ? value : []
    def num(value) = value.to_s =~ /\A-?\d+\z/ ? value.to_i : 0
    def numeric_weight(value) = value.is_a?(Numeric) && value.positive? ? value : 1

    def parse_ts(value)
      return nil if value.nil?
      return Time.at(value / 1000.0).utc if value.is_a?(Numeric)

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def ts_local(time)
      zone = ActiveSupport::TimeZone[DEFAULT_TZ]
      time.in_time_zone(zone).strftime('%d/%m/%Y %H:%M')
    end
  end
end
