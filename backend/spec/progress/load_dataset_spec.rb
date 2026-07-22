# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 3.4/3.6 — o dataset de carga (93.000 tarefas) e os orçamentos
# de latência. O NÚMERO de statements é travado deterministicamente em
# query_budget_spec; aqui provamos que o dataset SEMEIA em ≤ 60 s (senão o
# orçamento apodrece por ninguém rodar) e medimos a latência da Visão Geral e do
# BulkRecompute de forma TOLERANTE — os p95 exatos da spec (120ms/8s) são o alvo
# em hardware de produção; no runner só pegamos regressão grosseira (EXECUCAO
# decisão 7 de G3).
RSpec.describe 'Dataset de carga e orçamentos de latência', :tenancy, :slow do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  it 'semeia 20×10×15×31 = 93.000 tarefas em ≤ 60 s, cache consistente' do
    t0 = clock
    in_workspace(ws) { seed_progress_load(ws.id) }
    dt = clock - t0

    counts = in_workspace(ws) { [Project.count, Cell.count, Robot.count, Task.count] }
    expect(counts).to eq([20, 200, 3000, 93_000])
    expect(dt).to be < 60, "seed levou #{dt.round(1)}s (> 60s)"

    # o cache foi materializado pelo BulkRecompute do seed
    sample = in_workspace(ws) { Robot.where('progress_cache > 0').first }
    expect(sample.progress_cache).to be_between(1, 100)
  end

  it 'Visão Geral e BulkRecompute rodam em tempo tolerante sobre a carga' do
    in_workspace(ws) { seed_progress_load(ws.id) }

    t0 = clock
    in_workspace(ws) { Progress::OverviewQuery.call(workspace_id: ws.id) }
    overview = clock - t0
    # alvo de produção: p95 ≤ 120ms. Teto tolerante no runner: 2s.
    expect(overview).to be < 2.0, "overview levou #{(overview * 1000).round}ms"

    t0 = clock
    in_workspace(ws) { Progress::BulkRecompute.call(workspace_id: ws.id) }
    bulk = clock - t0
    # alvo de produção: p95 ≤ 8s. Teto tolerante: 20s.
    expect(bulk).to be < 20.0, "bulk levou #{bulk.round(1)}s"
  end
end
