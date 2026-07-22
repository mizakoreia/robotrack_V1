# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 4.1/4.3 (§3.8/§5.1, D-R10) — a distribuição de status com os
# 4 glifos. As 4 linhas SEMPRE presentes (inclusive zeradas), e a soma das 4
# contagens SHALL ser igual ao total de tarefas dos metadados — uma tarefa contada
# em dois status, ou um status fora das 4 linhas, faz a soma divergir.
RSpec.describe 'commissioning-report — distribuição de status (D-R10)', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  before { in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) } }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)

  def seed(counts)
    in_workspace(ws) do
      p = Project.create!(name: 'P', position: 0)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      pos = 0
      counts.each do |status, n|
        prog = status == 'Concluído' ? 100 : 0
        n.times { create_task(r, desc: "T#{pos}", position: pos, status: status, progress: prog); pos += 1 }
      end
    end
  end

  it 'dataset 12/9/15/4 = 40: cada glifo com sua contagem e a soma bate o total' do
    seed('Concluído' => 12, 'Em Andamento' => 9, 'Pendente' => 15, 'N/A' => 4)
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    dist = body['status_distribution']

    expect(dist).to eq([
      { 'status' => 'Concluído', 'glyph' => '✓', 'label' => 'Concluído', 'count' => 12 },
      { 'status' => 'Em Andamento', 'glyph' => '◐', 'label' => 'Em andamento', 'count' => 9 },
      { 'status' => 'Pendente', 'glyph' => '○', 'label' => 'Pendente', 'count' => 15 },
      { 'status' => 'N/A', 'glyph' => '—', 'label' => 'N/A', 'count' => 4 }
    ])
    expect(dist.sum { |d| d['count'] }).to eq(body['metadata']['counts']['tasks'])
    expect(body['metadata']['counts']['tasks']).to eq(40)
  end

  it 'status sem nenhuma tarefa aparece com 0 (linha não é omitida)' do
    seed('Pendente' => 3) # nenhum N/A, nenhum Concluído, nenhum Em Andamento
    get '/api/v1/commissioning_report?scope=all', headers: headers
    dist = JSON.parse(response.body)['status_distribution']
    expect(dist.map { |d| d['status'] }).to eq(['Concluído', 'Em Andamento', 'Pendente', 'N/A'])
    expect(dist.find { |d| d['status'] == 'N/A' }['count']).to eq(0)
    expect(dist.sum { |d| d['count'] }).to eq(3)
  end
end
