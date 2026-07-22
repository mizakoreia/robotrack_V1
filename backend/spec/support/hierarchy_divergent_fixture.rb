# frozen_string_literal: true

# hierarchy-screens 1.1 (§2.1 + §3.2 / D15) — a fixture OBRIGATÓRIA onde as duas
# métricas DIVERGEM. Todo teste que toca ponderado E contagem crua usa esta: um
# dataset onde os dois valores coincidem passaria com uma implementação unificada,
# e é exatamente assim que a unificação silenciosa (o risco nº 1 do D15) entra.
#
# UM robô, 4 tarefas:
#   - 1 tarefa peso 2, 100 %, `Concluído`
#   - 3 tarefas peso 1, 0 %, `Pendente`
#
# Ponderado §2.1 (Σ peso×progresso ÷ Σ peso×100):  2×100 / (2+1+1+1)×100 = 40
# Contagem crua §3.2 (concluídas ÷ total):          1 / 4               = 25 %
#
# DIVERGÊNCIA REGISTRADA: o design.md/tarefa dizem "peso 5 + três peso 1". Sob a
# fórmula ponderada JÁ ENTREGUE por `progress-rollup` (view robot_weighted_progress:
# Σ peso×progresso ÷ Σ peso×100) esses pesos dão 63, não 40. O alvo declarado do
# D15 — e a asserção da tarefa 4.6 ("anel 40 %") — é 40; a razão de peso que produz
# 40 é 2:1 (2/(2+3) = 0,4). Escolhi os pesos que batem o NÚMERO que os testes
# citam, não os pesos do texto que contradizem a fórmula. Ver EXECUCAO decisão 4.
module HierarchyDivergentFixture
  Ids = Struct.new(:workspace, :project, :cell, :robot, keyword_init: true)

  # Valores esperados, para os testes referenciarem sem recalcular.
  EXPECTED = {
    weighted: 40,
    raw: { completed: 1, total: 4, percent: 25 }
  }.freeze

  APPLICATION = 'Solda Ponto' # valor do enum fechado (chk_robots_application)

  # Pressupõe contexto de tenant já aberto (use dentro de `in_workspace`).
  def seed_divergent_progress
    project = Project.create!(name: 'Linha 300 — Carroceria')
    cell = Cell.create!(project_id: project.id, name: 'Célula 01')
    robot = Robot.create!(cell_id: cell.id, name: 'R01 - Solda', application: APPLICATION)

    Task.create!(robot_id: robot.id, workspace_id: robot.workspace_id,
                 cat: 'A. Hardware', desc: 'Fixação da base', position: 0,
                 weight: 2, progress: 100, status: 'Concluído')
    3.times do |i|
      Task.create!(robot_id: robot.id, workspace_id: robot.workspace_id,
                   cat: 'A. Hardware', desc: "Ajuste #{i + 1}", position: i + 1,
                   weight: 1, progress: 0, status: 'Pendente')
    end

    # Rows criados via model (sem cascata) — popula `progress_cache` uma vez para os
    # endpoints de overview (que LEEM o cache, nunca recalculam por linha, D-C).
    ::Progress::BulkRecompute.call(workspace_id: robot.workspace_id)

    Ids.new(workspace: robot.workspace_id, project: project.id, cell: cell.id, robot: robot.id)
  end

  # D15 — a fixture é INVÁLIDA se ponderado == crua: sem divergência ela não prova
  # nada. Chamado pelos testes que dependem da divergência.
  def assert_divergent!(expected = EXPECTED)
    return unless expected[:weighted] == expected[:raw][:percent]

    raise "fixture de divergência inválida: ponderado == crua (#{expected[:weighted]})"
  end
end

RSpec.configure do |config|
  config.include HierarchyDivergentFixture, :tenancy
end
