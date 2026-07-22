# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 2.1/2.2/2.4 (§2.1/§3.8, D-R5/D15) — o CARIMBO: média
# aritmética simples do progresso PONDERADO dos projetos do escopo, arredondada.
# NUNCA a contagem crua (§3.2). O rótulo é função só do percentual.
#
# O teste obrigatório de D15 usa um dataset onde ponderado e cru DIVERGEM: se
# alguém "consertar" o relatório para bater com o hub (que mostra o cru), a falha
# aparece aqui.
RSpec.describe 'commissioning-report — carimbo ponderado (D-R5/D15)', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  before { in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) } }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)

  # Cria um projeto→célula→robô e as tarefas (peso, progresso, status), materializa
  # o progress_cache ponderado (BulkRecompute) e devolve o projeto.
  def project_with(tasks:, name: 'P', pos: 0)
    p = in_workspace(ws) do
      pr = Project.create!(name: name, position: pos)
      c = Cell.create!(project_id: pr.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      tasks.each_with_index do |(w, prog, st), i|
        create_task(r, desc: "T#{i}", position: i, weight: w, progress: prog, status: st)
      end
      pr
    end
    in_workspace(ws) { Progress::BulkRecompute.call(workspace_id: ws.id) }
    p
  end

  def stamp
    get '/api/v1/commissioning_report?scope=all', headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['stamp']
  end

  it 'D15: peso 9 @100 (Concluído) + peso 1 @0 (Pendente) carimba 90, NÃO 50 (cru)' do
    project_with(tasks: [[9, 100, 'Concluído'], [1, 0, 'Pendente']])
    s = stamp
    expect(s['percent']).to eq(90)     # ponderado
    expect(s['percent']).not_to eq(50) # a contagem crua (1/2) seria 50
    expect(s['label']).to eq('EM ANDAMENTO')
  end

  it '100% carimba CONCLUÍDO' do
    project_with(tasks: [[1, 100, 'Concluído'], [1, 100, 'Concluído']])
    expect(stamp).to eq('percent' => 100, 'label' => 'CONCLUÍDO')
  end

  it '0% carimba PENDENTE' do
    project_with(tasks: [[1, 0, 'Pendente'], [1, 0, 'Pendente']])
    expect(stamp).to eq('percent' => 0, 'label' => 'PENDENTE')
  end

  it 'média entre projetos é SIMPLES, não ponderada por tamanho (100 e 0 → 50)' do
    project_with(name: 'Linha A', pos: 0, tasks: [[1, 100, 'Concluído']])           # 1 robô @100
    project_with(name: 'Linha B', pos: 1, tasks: [[1, 0, 'Pendente'], [1, 0, 'Pendente'], [1, 0, 'Pendente']]) # maior @0
    s = stamp
    expect(s['percent']).to eq(50)      # (100 + 0) / 2
    expect(s['label']).to eq('EM ANDAMENTO')
  end

  it 'escopo sem projeto algum: 0 / PENDENTE + estrutura zerada' do
    in_workspace(ws) { Progress::BulkRecompute.call(workspace_id: ws.id) }
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    expect(body['stamp']).to eq('percent' => 0, 'label' => 'PENDENTE')
    expect(body['metadata']['counts']).to eq('projects' => 0, 'cells' => 0, 'robots' => 0, 'tasks' => 0)
  end

  it 'tarefas todas N/A chegam a 100 ponderado e carimbam CONCLUÍDO (rótulo por %, não por status)' do
    project_with(tasks: [[1, 0, 'N/A'], [1, 0, 'N/A']])
    expect(stamp).to eq('percent' => 100, 'label' => 'CONCLUÍDO')
  end
end
