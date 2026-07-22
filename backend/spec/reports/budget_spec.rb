# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 8.1 (D-R8) — os três tetos de Reports::Budget, exercitados
# com limiares REBAIXADOS via stub_const (o dataset real de 2.300 tarefas mora no
# teste de carga 8.4). O truncamento NUNCA é silencioso: aviso no documento +
# `(+N entradas anteriores omitidas)` por tarefa truncada.
RSpec.describe 'commissioning-report — orçamento de volume', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  before { in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) } }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)

  # 1 projeto → 1 célula → 1 robô → N tarefas; a primeira com `advances` entradas
  # legadas (legacy dispensa `by`/comment) em minutos crescentes.
  def seed(tasks:, advances: 0)
    in_workspace(ws) do
      p = Project.create!(name: 'Linha A', position: 0)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      list = Array.new(tasks) { |i| create_task(r, desc: "T#{i}", position: i, status: 'Em Andamento', progress: 50) }
      base = Time.zone.parse('2026-07-01 08:00')
      advances.times do |i|
        TaskAdvance.create!(task_id: list.first.id, author_name_snapshot: "Autor #{i}",
                            from_progress: 0, to_progress: 50, legacy: true,
                            recorded_at: base + i.minutes, created_at: base + i.minutes)
      end
      list
    end
  end

  it 'acima de WARN_TASKS avisa (escopo grande) mas NÃO trunca' do
    stub_const('Reports::Budget::WARN_TASKS', 2)
    seed(tasks: 3, advances: 3)
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    expect(body['warnings']).to eq([I18n.t('report.v1.warning_large_scope')])
    all_advances = body['tree'][0]['cells'][0]['robots'][0]['tasks'].sum { |t| t['advances'].size }
    expect(all_advances).to eq(3) # nada omitido
    expect(body['tree'][0]['cells'][0]['robots'][0]['tasks'].map { |t| t['truncated_notice'] }.compact).to be_empty
  end

  it 'acima de TRUNCATE_ADVANCES trunca às KEEP_PER_TASK mais recentes e ANUNCIA (+N omitidas)' do
    stub_const('Reports::Budget::TRUNCATE_ADVANCES', 5)
    stub_const('Reports::Budget::KEEP_PER_TASK', 2)
    seed(tasks: 2, advances: 7)
    get '/api/v1/commissioning_report?scope=all', headers: headers
    body = JSON.parse(response.body)
    expect(body['warnings']).to include(I18n.t('report.v1.warning_truncated'))
    task = body['tree'][0]['cells'][0]['robots'][0]['tasks'].find { |t| t['advances'].any? }
    expect(task['advances'].size).to eq(2)
    # sobrevivem as MAIS RECENTES por recorded_at (as duas últimas: autores 5 e 6)
    expect(task['advances'].map { |a| a['author'] }).to eq(['Autor 5', 'Autor 6'])
    expect(task['truncated_notice']).to eq('(+5 entradas anteriores omitidas)')
  end

  it 'acima de MAX_TASKS recusa com 422 ANTES de montar o payload' do
    stub_const('Reports::Budget::MAX_TASKS', 2)
    seed(tasks: 3)
    get '/api/v1/commissioning_report?scope=all', headers: headers
    expect(response).to have_http_status(422)
    body = JSON.parse(response.body)
    expect(body['error']).to include('scope=project') # instrui a emitir por projeto
    expect(body).not_to have_key('tree') # nenhum payload montado
  end

  it 'escopo típico não dispara aviso algum' do
    seed(tasks: 3, advances: 2)
    get '/api/v1/commissioning_report?scope=all', headers: headers
    expect(JSON.parse(response.body)['warnings']).to eq([])
  end
end
