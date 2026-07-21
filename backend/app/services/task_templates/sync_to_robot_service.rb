# frozen_string_literal: true

module TaskTemplates
  # task-catalog 5.2/5.3 (§2.6, D-TC-6) — sincronização retroativa: aplica ao robô
  # os templates que FALTAM, sem tocar nas tarefas que já existem.
  #
  # 1. `SELECT ... FOR UPDATE` na linha do robô — serializa syncs concorrentes do
  #    mesmo robô (a segunda espera, relê as tarefas já criadas e adiciona 0).
  # 2. Templates aplicáveis por `ApplicabilityFilter` contra `robot.application`.
  # 3. Diff por `lower(btrim(desc))` contra as tarefas do robô — pula todo
  #    template cuja `desc` já exista (insensível a caixa e espaços nas bordas).
  # 4. `insert_all` SÓ das faltantes, com `progress: 0`, `status: "Pendente"`, sem
  #    responsável, `weight` copiado do template, `position` continuando a maior
  #    atual. NUNCA upsert — zeraria progresso/histórico das existentes.
  #
  # Retorna `{ added_count: N }` = linhas EFETIVAMENTE inseridas, não o tamanho do
  # conjunto aplicável. O índice único `(robot_id, lower(btrim(desc)))` (de
  # robot-tasks) é o backstop real contra a corrida — se duas syncs escaparem do
  # lock, a segunda estoura `23505` e a transação inteira reverte (nunca 58).
  class SyncToRobotService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(robot_id:)
      robot = ::Robot.find_by(id: robot_id)
      return error_response('not_found', 404) if robot.nil?

      added = 0
      ActiveRecord::Base.transaction do
        robot.lock! # SELECT ... FOR UPDATE

        existing = ::Task.where(robot_id: robot.id).pluck(:desc).map { |d| normalize(d) }.to_set
        start = (::Task.where(robot_id: robot.id).maximum(:position) || -1) + 1

        rows = []
        applicable_templates(robot.application).each do |template|
          key = normalize(template.desc)
          next if existing.include?(key)

          existing.add(key)
          rows << {
            robot_id: robot.id, workspace_id: robot.workspace_id,
            cat: template.cat, desc: template.desc, weight: template.weight,
            position: start + rows.size, progress: 0, status: 'Pendente'
          }
        end

        ::Task.insert_all!(rows) if rows.any?
        added = rows.size
      end

      success_response({ added_count: added }, 200)
    rescue ActiveRecord::RecordNotUnique
      # Corrida que passou pelo lock (ou colisão de desc): o índice único barrou e
      # a transação reverteu. Contagem não mentirosa (§2.6).
      error_response('sync_conflict', 409)
    end

    private

    def applicable_templates(application)
      ApplicabilityFilter.scope_for(application)
        .order(Arel.sql('cat COLLATE "C", "desc" COLLATE "C"'))
        .to_a
    end

    def normalize(desc)
      desc.to_s.strip.downcase
    end
  end
end
