# frozen_string_literal: true

module Reports
  # commissioning-report 1.2/1.4 (§3.8, D-R1/D-R5/D-R8) — monta o Protocolo de
  # Comissionamento como um PAYLOAD CONGELADO, inteiramente no servidor: o cliente
  # não soma, não calcula média, não escolhe autor (D-R1). Leitura pura.
  #
  # Escopo `all` (workspace inteiro, via RLS) ou `project` (um projeto do workspace);
  # qualquer outro valor → 400. Projeto inexistente/de outro workspace → 404 (RLS
  # oculta → find_by nil), sem vazar nome nem contagens.
  #
  # Orçamento: ≤5 queries CONSTANTES no nº de projetos (D-R8):
  #   Q1 árvore projeto/célula/robô (LEFT JOINs, tolerante a nível vazio)
  #   Q2 tarefas + responsáveis agregados
  #   Q3 avanços por task_id = ANY(...)
  #   Q4 contagens por status
  #   Q5 autoria das conclusões (Reports::CompletionAuthorship)
  class CommissioningReportService
    include ApiResponseHandler

    VALID_SCOPES = %w[all project].freeze

    def initialize(context:)
      @context = context
    end

    def call(scope:, project_id: nil, now: Time.current, time_zone: DocumentId::DEFAULT_TIME_ZONE)
      return error_response('escopo_invalido', 400) unless VALID_SCOPES.include?(scope)

      if scope == 'project'
        return error_response('project_id_obrigatorio', 400) if project_id.blank?
        return error_response('not_found', 404) if ::Project.find_by(id: project_id).nil?
      end

      tree_rows = fetch_tree(scope, project_id)
      task_rows = fetch_tasks(scope, project_id)
      task_ids  = task_rows.map { |t| t['id'] }
      advances  = fetch_advances(task_ids)
      status_counts = fetch_status_counts(scope, project_id)
      authorship = CompletionAuthorship.resolve(task_ids.select { |id| completed?(task_rows, id) })

      success_response(build_payload(
        scope: scope, now: now, time_zone: time_zone,
        tree_rows: tree_rows, task_rows: task_rows, advances: advances,
        status_counts: status_counts, authorship: authorship
      ))
    end

    private

    attr_reader :context

    def t(key, **args) = I18n.t("report.v1.#{key}", **args)

    # ---- Queries (constantes em N) ----

    def fetch_tree(scope, project_id)
      where, binds = scope_filter('p.id', scope, project_id)
      conn.exec_query(<<~SQL, 'reports.tree', binds).to_a
        SELECT p.id AS p_id, p.name AS p_name, p.position AS p_pos, p.progress_cache AS p_prog,
               c.id AS c_id, c.name AS c_name, c.position AS c_pos, c.progress_cache AS c_prog,
               r.id AS r_id, r.name AS r_name, r.application AS r_app, r.position AS r_pos, r.progress_cache AS r_prog
        FROM projects p
        LEFT JOIN cells  c ON c.project_id = p.id
        LEFT JOIN robots r ON r.cell_id = c.id
        #{where}
        ORDER BY p.position, p.id, c.position, c.id, r.position, r.id
      SQL
    end

    def fetch_tasks(scope, project_id)
      where, binds = scope_filter('c.project_id', scope, project_id)
      conn.exec_query(<<~SQL, 'reports.tasks', binds).to_a
        SELECT t.id, t.robot_id, t.cat, t."desc" AS description, t.status, t.progress, t.position,
               COALESCE(
                 array_agg(pe.name ORDER BY pe.name) FILTER (WHERE pe.id IS NOT NULL),
                 ARRAY[]::text[]
               ) AS assignees
        FROM tasks t
        JOIN robots r ON r.id = t.robot_id
        JOIN cells  c ON c.id = r.cell_id
        LEFT JOIN task_assignees ta ON ta.task_id = t.id
        LEFT JOIN people pe ON pe.id = ta.person_id
        #{where}
        GROUP BY t.id
        ORDER BY t.position, t.id
      SQL
    end

    def fetch_advances(task_ids)
      return {} if task_ids.blank?

      # ids vêm do banco (trusted); `exec_query` não casta bind de array p/ ANY(),
      # então montamos a lista de uuids quotada.
      ids = task_ids.map { |i| conn.quote(i) }.join(',')
      rows = conn.exec_query(<<~SQL, 'reports.advances').to_a
        SELECT task_id, recorded_at, created_at, from_progress, to_progress, comment, author_name_snapshot
        FROM task_advances
        WHERE task_id = ANY(ARRAY[#{ids}]::uuid[])
        ORDER BY task_id, recorded_at ASC, created_at ASC, id ASC
      SQL
      rows.group_by { |r| r['task_id'] }
    end

    def fetch_status_counts(scope, project_id)
      where, binds = scope_filter('c.project_id', scope, project_id)
      rows = conn.exec_query(<<~SQL, 'reports.status', binds).to_a
        SELECT t.status, COUNT(*) AS n
        FROM tasks t JOIN robots r ON r.id = t.robot_id JOIN cells c ON c.id = r.cell_id
        #{where}
        GROUP BY t.status
      SQL
      rows.each_with_object(Hash.new(0)) { |r, acc| acc[r['status']] = r['n'].to_i }
    end

    # scope=all → RLS já escopa ao workspace (sem filtro); scope=project → filtra a
    # coluna dada pelo project_id.
    def scope_filter(column, scope, project_id)
      return ['', []] if scope == 'all'

      ["WHERE #{column} = $1", [project_id]]
    end

    def conn = ActiveRecord::Base.connection

    def completed?(task_rows, id) = task_rows.any? { |t| t['id'] == id && t['progress'].to_i == 100 }

    # ---- Montagem do payload ----

    def build_payload(scope:, now:, time_zone:, tree_rows:, task_rows:, advances:, status_counts:, authorship:)
      document_id = DocumentId.for(now, time_zone)
      projects = assemble_tree(tree_rows, task_rows, advances)
      stamp = build_stamp(projects)
      counts = build_counts(tree_rows, task_rows)

      {
        scope: scope,
        header: { title: t(:title), workspace_name: context&.workspace&.name },
        stamp: stamp,
        document_id: document_id,
        metadata: {
          scope_label: scope == 'project' ? t(:scope_project) : t(:scope_all),
          document_id: document_id,
          issued_at: now.in_time_zone(time_zone).iso8601,
          generated_by: context&.person&.name,
          structure: t(:structure_format, **counts),
          counts: counts
        },
        status_distribution: build_distribution(status_counts),
        tree: projects,
        conclusions: build_conclusions(task_rows, authorship),
        warnings: [] # volume (G7)
      }
    end

    def build_stamp(projects)
      percents = projects.map { |p| p[:weighted_progress] }
      percent = percents.empty? ? 0 : (percents.sum.to_f / percents.size).round
      { percent: percent, label: stamp_label(percent) }
    end

    def stamp_label(percent)
      return t(:stamp_label_done) if percent == 100
      return t(:stamp_label_pending) if percent.zero?

      t(:stamp_label_in_progress)
    end

    def build_counts(tree_rows, task_rows)
      {
        projects: tree_rows.map { |r| r['p_id'] }.compact.uniq.size,
        cells: tree_rows.map { |r| r['c_id'] }.compact.uniq.size,
        robots: tree_rows.map { |r| r['r_id'] }.compact.uniq.size,
        tasks: task_rows.size
      }
    end

    def build_distribution(status_counts)
      StatusGlyph::STATUSES.map do |status|
        { status: status, glyph: StatusGlyph.for(status), label: distribution_label(status), count: status_counts[status] }
      end
    end

    def distribution_label(status)
      { 'Concluído' => t(:status_done), 'Em Andamento' => t(:status_in_progress),
        'Pendente' => t(:status_pending), 'N/A' => t(:status_na) }.fetch(status)
    end

    # Árvore aninhada projeto → célula → robô → tarefa (+ histórico), tolerante a
    # níveis vazios (LEFT JOIN traz linhas com c_id/r_id nulos).
    def assemble_tree(tree_rows, task_rows, advances)
      tasks_by_robot = task_rows.group_by { |t| t['robot_id'] }
      projects = {}
      tree_rows.each do |row|
        p = (projects[row['p_id']] ||= {
          id: row['p_id'], name: row['p_name'], weighted_progress: row['p_prog'].to_i, cells: {}
        })
        next if row['c_id'].nil?

        c = (p[:cells][row['c_id']] ||= {
          id: row['c_id'], name: row['c_name'], weighted_progress: row['c_prog'].to_i, robots: {}
        })
        next if row['r_id'].nil?

        c[:robots][row['r_id']] ||= {
          id: row['r_id'], name: row['r_name'], application: row['r_app'],
          weighted_progress: row['r_prog'].to_i,
          tasks: (tasks_by_robot[row['r_id']] || []).map { |tk| build_task(tk, advances) }
        }
      end
      # Hash → array preservando a ordem (as queries já vêm ordenadas por position).
      projects.values.map do |p|
        p[:cells] = p[:cells].values.map { |c| c[:robots] = c[:robots].values; c }
        p
      end
    end

    def build_task(tk, advances)
      {
        id: tk['id'], description: tk['description'], status: tk['status'],
        symbol: StatusGlyph.for(tk['status']), percent: tk['progress'].to_i,
        assignees: pg_array(tk['assignees']),
        advances: (advances[tk['id']] || []).map do |a|
          { recorded_at: a['recorded_at'], author: a['author_name_snapshot'],
            from: a['from_progress'].to_i, to: a['to_progress'].to_i, comment: a['comment'] }
        end
      }
    end

    def build_conclusions(task_rows, authorship)
      task_rows.select { |t| t['progress'].to_i == 100 }.map do |t|
        auth = authorship[t['id']]
        assignees = pg_array(t['assignees'])
        by = if auth then auth[:author]
             elsif assignees.any? then assignees.join(' · ')
             else t(:concluded_unknown)
             end
        { task_id: t['id'], description: t['description'], concluded_by: by, concluded_at: auth&.dig(:recorded_at) }
      end
    end

    # `array_agg` volta como string `{a,b}` no driver cru; normaliza para Array.
    def pg_array(value)
      return value if value.is_a?(Array)
      return [] if value.nil? || value == '{}'

      value.to_s.gsub(/\A\{|\}\z/, '').scan(/"([^"]*)"|([^,]+)/).map { |a, b| a || b }
    end
  end
end
