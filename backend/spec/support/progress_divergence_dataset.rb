# frozen_string_literal: true

# progress-rollup 1.5 (D15.b) — o dataset onde as DUAS métricas divergem em todos
# os níveis. Todo teste que exercita ponderado E contagem crua usa este dataset:
# um dataset onde elas coincidem passaria com uma implementação unificada, e é
# assim que a unificação silenciosa entra.
#
#  | Robô | Tarefas                                  | Ponderado §2.1 | Crua §3.2 |
#  | R1   | peso 3 @100 Concluído, peso 1 @0 Pendente | 75            | 50% (1/2) |
#  | R2   | 3 tarefas N/A                             | 100           | 0%  (0/3) |
#  | R3   | nenhuma tarefa                            | 0             | — (0/0)   |
#  | C1 = (75+100+0)/3                              | 58            | 20% (1/5) |
module ProgressDivergenceDataset
  Ids = Struct.new(:project, :cell, :r1, :r2, :r3, keyword_init: true)

  # Valores esperados, para os testes referenciarem sem recalcular.
  EXPECTED = {
    r1: { weighted: 75,  raw: { completed: 1, total: 2, percent: 50 } },
    r2: { weighted: 100, raw: { completed: 0, total: 3, percent: 0 } },
    r3: { weighted: 0,   raw: { completed: 0, total: 0, percent: 0 } },
    c1: { weighted: 58,  raw: { completed: 1, total: 5, percent: 20 } }
  }.freeze

  # Pressupõe contexto de tenant já aberto (use dentro de `in_workspace`).
  def seed_progress_divergence(robot_helper: method(:create_task))
    projeto = Project.create!(name: 'P-divergência')
    c1 = Cell.create!(project_id: projeto.id, name: 'C1')
    r1 = Robot.create!(cell_id: c1.id, name: 'R1')
    r2 = Robot.create!(cell_id: c1.id, name: 'R2')
    r3 = Robot.create!(cell_id: c1.id, name: 'R3')

    robot_helper.call(r1, desc: 'R1 pesada', weight: 3, progress: 100, status: 'Concluído', position: 0)
    robot_helper.call(r1, desc: 'R1 leve',   weight: 1, progress: 0,   status: 'Pendente',  position: 1)
    3.times { |i| robot_helper.call(r2, desc: "R2 na #{i}", weight: 1, progress: 0, status: 'N/A', position: i) }
    # R3 sem tarefas.

    # Os rows foram criados via model (sem cascata) — popula o cache uma vez, para
    # os testes que leem `progress_cache` (overview) verem os valores das views.
    ::Progress::BulkRecompute.call(workspace_id: projeto.workspace_id)

    Ids.new(project: projeto.id, cell: c1.id, r1: r1.id, r2: r2.id, r3: r3.id)
  end

  # D15.b — o dataset é INVÁLIDO se ponderado == crua onde a crua é definida
  # (R1, R2, C1). Chamado pelos testes que dependem da divergência.
  def assert_divergence!(expected = EXPECTED)
    %i[r1 r2 c1].each do |nivel|
      w = expected[nivel][:weighted]
      raw = expected[nivel][:raw][:percent]
      raise "dataset de divergência inválido: #{nivel} tem ponderado == crua (#{w})" if w == raw
    end
  end
end

RSpec.configure do |config|
  config.include ProgressDivergenceDataset, :tenancy
end
