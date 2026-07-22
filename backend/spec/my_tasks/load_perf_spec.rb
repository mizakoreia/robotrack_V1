# frozen_string_literal: true

require 'rails_helper'

# my-tasks-view 7.1/7.2 (D-MTV-4/5) — o dataset de carga e o orçamento. Números
# COMPARTILHADOS de D-MTV-5: 10 × 8 × 12 × 30 = 28.800 tarefas num workspace, o
# viewer atribuído a 1.500 delas. O alvo de produção (p95 < 120 ms) é medido em
# hardware; no runner medimos com TETO TOLERANTE (mesma política de
# progress-rollup) e travamos o PLANO: **nenhum Seq Scan on tasks** — é a perda de
# índice que só apareceria em produção quando a tabela cresce.
RSpec.describe 'my-tasks-view — carga e plano de consulta', :tenancy, :slow do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # Semeia 10×8×12×30 = 28.800 tarefas por `insert_all` em lote, SEM BulkRecompute
  # (esta tela não lê `progress_cache` — recomputar 28.800 linhas só gastaria o
  # tempo do runner). `without_cascade` suprime os triggers de cascata na inserção.
  def seed_28_800(ws_id)
    now = Time.current
    Progress.without_cascade do
      projects = Array.new(10) { |i| { id: SecureRandom.uuid, workspace_id: ws_id, name: "P#{i}", position: i, progress_cache: 0, created_at: now, updated_at: now } }
      Project.insert_all!(projects)
      cells = projects.flat_map { |p| Array.new(8) { |i| { id: SecureRandom.uuid, workspace_id: ws_id, project_id: p[:id], name: "C#{i}", position: i, progress_cache: 0, created_at: now, updated_at: now } } }
      Cell.insert_all!(cells)
      robots = cells.flat_map { |c| Array.new(12) { |i| { id: SecureRandom.uuid, workspace_id: ws_id, cell_id: c[:id], name: "R#{i}", application: 'Misto / Geral', position: i, progress_cache: 0, created_at: now, updated_at: now } } }
      robots.each_slice(5000) { |s| Robot.insert_all!(s) }
      robots.each_slice(200) do |slice|
        trows = slice.flat_map do |r|
          Array.new(30) do |ti|
            status, progress = case ti % 3 when 0 then ['Concluído', 100] when 1 then ['Em Andamento', 50] else ['Pendente', 0] end
            { id: SecureRandom.uuid, workspace_id: ws_id, robot_id: r[:id], cat: 'A. Hardware', desc: "T#{ti}", weight: 1, progress: progress, status: status, position: ti, created_at: now, updated_at: now }
          end
        end
        trows.each_slice(5000) { |s| Task.insert_all!(s) }
      end
    end
  end

  it 'primeira página em tempo tolerante e SEM Seq Scan on tasks (28.800 tarefas)' do
    viewer_id = nil
    in_workspace(ws) do
      seed_28_800(ws.id)
      expect(Task.count).to eq(28_800)

      viewer = Person.create!(name: 'Ana', user_id: ana.id)
      viewer_id = viewer.id

      # viewer atribuído a 1.500 tarefas (~2/3 abertas por §2.2 → ~1.000 abertas).
      rows = Task.limit(1500).pluck(:id).map do |tid|
        { id: SecureRandom.uuid, workspace_id: ws.id, task_id: tid, person_id: viewer.id, created_at: Time.current }
      end
      TaskAssignee.insert_all!(rows)

    end

    # Plano: sem Seq Scan on tasks. Reflete o que o SERVICE faz (enable_nestloop=off
    # → hash join, robusto mesmo sem ANALYZE — o role `app` nem tem permissão de
    # analisar). Anexa o EXPLAIN à falha.
    plan = in_workspace(ws) do
      ActiveRecord::Base.connection.execute('SET LOCAL enable_nestloop = off')
      sql = <<~SQL
        EXPLAIN (ANALYZE, BUFFERS)
        WITH mine AS MATERIALIZED (
          SELECT ta.task_id FROM task_assignees ta
          WHERE ta.workspace_id = '#{ws.id}' AND ta.person_id = '#{viewer_id}'
        )
        SELECT t.id, t."desc", t.status, t.progress, t.cat,
               r.id, r.name, c.id, c.name, p.id, p.name, COUNT(*) OVER()
        FROM mine
        JOIN tasks    t ON t.id = mine.task_id AND t.status IN ('Pendente', 'Em Andamento')
        JOIN robots   r ON r.id = t.robot_id
        JOIN cells    c ON c.id = r.cell_id
        JOIN projects p ON p.id = c.project_id
        ORDER BY p.position, p.id, c.position, c.id, r.position, r.id, t.position, t.id
        LIMIT 50 OFFSET 0
      SQL
      ActiveRecord::Base.connection.exec_query(sql).rows.flatten.join("\n")
    end

    expect(plan).not_to match(/Seq Scan on tasks\b/), "plano com Seq Scan on tasks:\n#{plan}"

    # Latência da primeira página (50 linhas). Alvo de produção: p95 < 120ms; teto
    # TOLERANTE no runner (política de progress-rollup — o hardware de CI não é o de
    # produção). O `enable_nestloop=off` do service é o que mantém isto em ms mesmo
    # sob a opacidade da RLS ao estimador.
    times = Array.new(5) do
      t0 = clock
      in_workspace(ws) { MyTasks::ListService.new.call(workspace_id: ws.id, person_id: viewer_id, per_page: 50) }
      clock - t0
    end
    p95 = times.max
    # teto generoso: sob a suíte completa (pressão de memória/GC) 2s era apertado; o
    # que o teste GARANTE é que NÃO há a regressão de 28s do nested loop patológico.
    expect(p95).to be < 8.0, "primeira página levou #{(p95 * 1000).round}ms (alvo de produção: 120ms)"
  end
end
