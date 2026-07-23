# frozen_string_literal: true

require 'rails_helper'

# quality-and-accessibility 8.2 (D-QA-6) — a assinatura REAL de N+1 é a contagem de
# query CRESCER com o tamanho do dataset. Um teto absoluto (`issue_at_most`) passa
# folgado com 3 projetos: o N+1 gera só 3 queries extras. Aqui medimos DOIS tamanhos
# e exigimos a MESMA contagem — um robô com muitas tarefas/responsáveis tem de custar
# o mesmo número de queries que um sem nenhum. Complementa os tetos absolutos (que
# seguem em hierarchy_overview_spec/progress_overview_spec), não os substitui.
RSpec.describe 'q&a 8.2 — contagem de query INVARIANTE ao tamanho', :tenancy, type: :model do
  let(:ana) { create(:user, name: 'Ana Dona') }

  def build(ws, projects:, cells:, robots:, assignees: 0)
    in_workspace(ws) do
      people = Array.new(assignees) { |i| Person.create!(name: "Resp #{i}") }
      projects.times do |pi|
        proj = create_project(ws, name: "P#{pi}", position: pi)
        cells.times do |ci|
          cel = create_cell(proj, name: "C#{pi}-#{ci}", position: ci)
          robots.times do |ri|
            rob = create_robot(cel, name: "R#{pi}#{ci}#{ri}", position: ri)
            create_task(rob, desc: 'T', weight: 1, progress: 50, status: 'Em Andamento',
                             assignees: people)
          end
        end
      end
      Progress::BulkRecompute.call(workspace_id: ws.id)
    end
  end

  it 'Overview e Progress::OverviewQuery não crescem em queries com o dataset (nem com responsáveis)' do
    small = make_workspace(owner: ana, name: 'WS Pequeno')
    large = make_workspace(owner: create(:user, name: 'Bruno Dono'), name: 'WS Grande')
    build(small, projects: 1, cells: 2, robots: 2, assignees: 0)
    build(large, projects: 4, cells: 6, robots: 5, assignees: 2)

    endpoints = {
      'Hierarchy::OverviewService' => ->(ws) { Hierarchy::OverviewService.call(workspace_id: ws.id) },
      'Progress::OverviewQuery' => ->(ws) { Progress::OverviewQuery.call(workspace_id: ws.id) }
    }

    endpoints.each do |name, call|
      qs = in_workspace(small) { count_queries { call.call(small) } }
      ql = in_workspace(large) { count_queries { call.call(large) } }
      expect(ql).to eq(qs),
                    "#{name}: #{qs} SELECT no dataset pequeno vs #{ql} no grande — " \
                    'a contagem cresce com N (assinatura de N+1)'
    end
  end
end
