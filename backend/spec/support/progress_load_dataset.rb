# frozen_string_literal: true

require 'pg'

# progress-rollup 3.4 — o dataset de CARGA, compartilhado com quality-and-
# accessibility. Full: 20 projetos × 10 células × 15 robôs × 31 tarefas = 3.000
# robôs, 93.000 tarefas, num único workspace. Semeado por `insert_all` em lote,
# sob `without_cascade`, com UM `BulkRecompute` no fim — tem de caber em ≤ 60 s
# senão ninguém roda o orçamento e ele apodrece.
#
# `scale:` permite uma amostra menor para os testes que só precisam de N projetos
# (o orçamento de query roda com 20 projetos, não com 93k tarefas).
module ProgressLoadDataset
  DEFAULT = { projects: 20, cells: 10, robots: 15, tasks: 31 }.freeze

  # Pressupõe contexto de tenant aberto. Devolve o workspace_id.
  def seed_progress_load(workspace_id, scale: {})
    s = DEFAULT.merge(scale)
    ::Progress.without_cascade do
      insert_load(workspace_id, s)
    end
    # ANALYZE ANTES de medir: `insert_all` de dezenas de milhares de linhas não
    # atualiza pg_statistic, e o autovacuum ainda não rodou — o otimizador vê
    # rows≈1 e escolhe nested-loop em cascata (para cada robô, re-varre TODAS as
    # tasks do workspace por index_tasks_on_workspace_id → ~3k×93k comparações,
    # ~15 min). Com estatística fresca o plano vira hash-join (~80 ms). Em produção
    # o BulkRecompute roda sobre workspaces já analisados (autovacuum/atividade
    # prévia); o benchmark tem de medir ESSE steady-state, não a patologia de
    # stats frias. ANALYZE exige papel dono → conexão do migrator (o app não pode).
    analyze_progress_tables
    ::Progress::BulkRecompute.call(workspace_id: workspace_id)
    workspace_id
  end

  private

  def analyze_progress_tables
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    conn = PG.connect(
      host: cfg[:host] || 'localhost', port: cfg[:port] || 5432, dbname: cfg[:database],
      user: ENV.fetch('MIGRATOR_DB_USER', 'robotrack_migrator'),
      password: ENV.fetch('MIGRATOR_DB_PASSWORD', 'mig_dev_pw')
    )
    conn.exec('ANALYZE projects, cells, robots, tasks')
  ensure
    conn&.close
  end

  def insert_load(ws, s)
    now = Time.current
    project_rows = Array.new(s[:projects]) do |pi|
      { id: SecureRandom.uuid, workspace_id: ws, name: "P#{pi}", position: pi,
        progress_cache: 0, created_at: now, updated_at: now }
    end
    ::Project.insert_all!(project_rows)

    cell_rows = project_rows.flat_map do |p|
      Array.new(s[:cells]) do |ci|
        { id: SecureRandom.uuid, workspace_id: ws, project_id: p[:id], name: "C#{ci}", position: ci,
          progress_cache: 0, created_at: now, updated_at: now }
      end
    end
    cell_rows.each_slice(5000) { |slice| ::Cell.insert_all!(slice) }

    robot_rows = cell_rows.flat_map do |c|
      Array.new(s[:robots]) do |ri|
        { id: SecureRandom.uuid, workspace_id: ws, cell_id: c[:id], name: "R#{ri}",
          application: 'Misto / Geral', position: ri, progress_cache: 0, created_at: now, updated_at: now }
      end
    end
    robot_rows.each_slice(5000) { |slice| ::Robot.insert_all!(slice) }

    # Tarefas: 1/3 Concluído@100, 1/3 Em Andamento@50, 1/3 Pendente@0 — dá números
    # não-triviais nas duas métricas.
    robot_rows.each_slice(200) do |robot_slice|
      task_rows = robot_slice.flat_map do |r|
        Array.new(s[:tasks]) do |ti|
          status, progress = case ti % 3
                             when 0 then ['Concluído', 100]
                             when 1 then ['Em Andamento', 50]
                             else ['Pendente', 0]
                             end
          { id: SecureRandom.uuid, workspace_id: ws, robot_id: r[:id], cat: 'A. Hardware',
            desc: "T#{ti}", weight: 1, progress: progress, status: status, position: ti,
            created_at: now, updated_at: now }
        end
      end
      task_rows.each_slice(5000) { |slice| ::Task.insert_all!(slice) }
    end
  end
end

RSpec.configure do |config|
  config.include ProgressLoadDataset, :tenancy
end
