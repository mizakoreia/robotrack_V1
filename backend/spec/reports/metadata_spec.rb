# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 3.2/3.3 (§3.8, D-R6) — o bloco de metadados: escopo, id,
# emissão, gerado por, e a estrutura contando SÓ o escopo emitido. O id é o MESMO
# no topo do payload e nos metadados (e no rodapé, G6) — gerado uma vez.
RSpec.describe 'commissioning-report — metadados', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Marina Alves') }
  let(:ws)    { make_workspace(owner: owner) }
  before { in_workspace(ws) { Person.create!(name: 'Marina Alves', user_id: owner.id) } }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)

  def seed(name:, cells:, robots:, tasks:, pos: 0)
    in_workspace(ws) do
      p = Project.create!(name: name, position: pos)
      cells.times do |ci|
        c = Cell.create!(project_id: p.id, name: "C#{ci}", position: ci)
        robots.times do |ri|
          r = Robot.create!(cell_id: c.id, name: "R#{ri}", application: 'Solda Ponto', position: ri)
          tasks.times { |ti| create_task(r, desc: "T#{ti}", position: ti, status: 'Pendente', progress: 0) }
        end
      end
      p
    end
  end

  it 'id do topo == id dos metadados (gerado uma vez), e generated_by traz o autor' do
    seed(name: 'Linha A', cells: 1, robots: 1, tasks: 1)
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    expect(body['document_id']).to eq(body['metadata']['document_id'])
    expect(body['document_id']).to match(/\ART-\d{8}-\d{4}\z/)
    expect(body['metadata']['generated_by']).to eq('Marina Alves')
    expect(body['metadata']['issued_at']).to be_present
  end

  it 'estrutura conta APENAS o escopo emitido (projeto de 3 células, 7 robôs, 210 tarefas)' do
    seed(name: 'Fora', cells: 1, robots: 1, tasks: 1, pos: 0)          # outro projeto, fora
    alvo = seed(name: 'Alvo', cells: 3, robots: 7, tasks: 10, pos: 1)  # 3×7×10 = 210 tarefas
    get "/api/v1/commissioning_report?scope=project&project_id=#{alvo.id}", headers: headers
    body = JSON.parse(response.body)
    expect(body['metadata']['counts']).to eq('projects' => 1, 'cells' => 3, 'robots' => 21, 'tasks' => 210)
    expect(body['metadata']['structure']).to eq('1 projeto(s) · 3 célula(s) · 21 robô(s) · 210 tarefa(s)')
    expect(body['metadata']['scope_label']).to eq('Projeto')
  end
end
