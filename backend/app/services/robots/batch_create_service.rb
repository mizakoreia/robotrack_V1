# frozen_string_literal: true

module Robots
  # robot-tasks 5.2–5.4 (§2.5, §1.3, D-RT-4, D-RT-5) — cria a leva de robôs numa
  # ÚNICA transação e materializa as tarefas-base filtradas pela Aplicação.
  #
  # Cada robô nasce com CÓPIA por valor (`cat`/`desc`/`weight`) dos templates que
  # passam no filtro §2.5 (`TaskTemplates::ApplicabilityFilter`), `progress: 0`,
  # `status: 'Pendente'`, sem responsável, e `position` pela ordem lexicográfica
  # de `(cat, desc)` — a MESMA collation binária do catálogo (task-catalog 3.5),
  # congelada na criação (§1.3). Sem `template_id`: editar um template depois não
  # altera tarefa já criada (§2.6 é a saída).
  #
  # `insert_all` (não `create!` em loop) com `workspace_id` explícito em CADA hash
  # de robô e de tarefa (D-RT-5): `insert_all` pula callbacks E `default_scope`,
  # então sem o `workspace_id` a RLS rejeita o INSERT e a leva inteira faz
  # rollback — nada de robôs sem tarefas. O advisory lock do escopo (célula)
  # serializa levas concorrentes, como `PositionScoped`.
  class BatchCreateService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(cell_id:, application:, robots:)
      unless ::Robot::APPLICATIONS.include?(application)
        return error_response('invalid_application', 422, details: { allowed: ::Robot::APPLICATIONS })
      end

      cell = ::Cell.find_by(id: cell_id)
      return error_response('not_found', 404) if cell.nil?

      normalized = BatchNormalizer.call(robots)
      return error_response('empty_batch', 422) if normalized.empty?

      workspace_id = cell.workspace_id
      templates = applicable_templates(application)

      ActiveRecord::Base.transaction do
        # progress-rollup 2.5 — o caminho em massa suprime a cascata por linha
        # (50 robôs × 31 tarefas seriam até 1.550 recálculos) e recalcula o
        # workspace inteiro em 3 statements antes do commit.
        ::Progress.without_cascade do
          ::Robot.lock_position_scope!(cell_id)
          robot_rows = build_robot_rows(normalized, cell_id, workspace_id, application)
          ::Robot.insert_all!(robot_rows)

          task_rows = build_task_rows(robot_rows, templates, workspace_id)
          ::Task.insert_all!(task_rows) if task_rows.any?

          @created = robot_rows
        end
        ::Progress::BulkRecompute.call(workspace_id: workspace_id)
      end

      # realtime-collaboration 3.5 — UM envelope agregado `robot.batch_created`
      # (não 50 `robot.created`: o `insert_all` nem dispara callback), pós-commit
      # da request. Invalida cell/project/overview pelo `scope`, sem N broadcasts
      # nem N contenções na linha `realtime_seq`.
      ::Realtime.after_commit do
        ::Realtime::PublisherService.publish_aggregate(
          workspace_id: workspace_id, type: 'robot.batch_created',
          scope: { project_id: cell.project_id, cell_id: cell_id }
        )
      end

      success_response(
        { robots: @created.map { |r| r.slice(:id, :name, :application, :position) },
          robot_count: @created.size, tasks_per_robot: templates.size },
        201
      )
    rescue ActiveRecord::RecordNotUnique => e
      # index_robots_on_cell_lower_name: nome colidindo com robô já existente na
      # célula (o índice único é de commissioning-hierarchy — ver EXECUCAO
      # decisão 9). A leva inteira faz rollback.
      error_response(e.message.include?('cell_lower_name') ? 'name_taken' : 'conflict', 422)
    end

    private

    def applicable_templates(application)
      TaskTemplates::ApplicabilityFilter
        .scope_for(application)
        .order(Arel.sql('cat COLLATE "C", "desc" COLLATE "C"'))
        .to_a
    end

    def build_robot_rows(normalized, cell_id, workspace_id, application)
      start = (::Robot.where(cell_id: cell_id).maximum(:position) || -1) + 1
      normalized.each_with_index.map do |pair, i|
        {
          id: pair[:id] || SecureRandom.uuid,
          workspace_id: workspace_id,
          cell_id: cell_id,
          name: pair[:name],
          application: application,
          position: start + i
        }
      end
    end

    def build_task_rows(robot_rows, templates, workspace_id)
      robot_rows.flat_map do |robot|
        templates.each_with_index.map do |template, pos|
          {
            robot_id: robot[:id],
            workspace_id: workspace_id,
            cat: template.cat,
            desc: template.desc,
            weight: template.weight,
            position: pos,
            progress: 0,
            status: 'Pendente'
          }
        end
      end
    end
  end
end
