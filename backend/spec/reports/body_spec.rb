# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 5.x/6.x (§3.8, D8/D-R7/D11) — o corpo hierárquico, o
# histórico por tarefa (recorded_at, NUNCA created_at) e as Conclusões (autoria =
# última entrada que chegou a 100, com dois fallbacks).
RSpec.describe 'commissioning-report — corpo, histórico e conclusões', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  let(:person) { in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) } }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)

  def report
    get '/api/v1/commissioning_report?scope=all', headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  def advance!(task, by:, name:, to:, from: 0, recorded_at:, created_at: nil, comment: 'ok')
    in_workspace(ws) do
      TaskAdvance.create!(
        task_id: task.id, workspace_id: ws.id, by: by, author_name_snapshot: name,
        from_progress: from, to_progress: to, comment: comment,
        recorded_at: recorded_at, created_at: created_at || recorded_at
      )
    end
  end

  describe 'histórico (5.3, D8)' do
    it 'exibe recorded_at (14:02), não created_at (17:41); created_at NÃO existe no payload' do
      person
      task = nil
      in_workspace(ws) do
        p = Project.create!(name: 'P', position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
        task = create_task(r, desc: 'Fixar', position: 0, status: 'Em Andamento', progress: 45)
      end
      advance!(task, by: person.id, name: 'Ana', to: 45,
               recorded_at: Time.utc(2026, 7, 18, 17, 2), created_at: Time.utc(2026, 7, 18, 20, 41))

      adv = report['tree'][0]['cells'][0]['robots'][0]['tasks'][0]['advances'][0]
      expect(Time.parse(adv['recorded_at'])).to eq(Time.utc(2026, 7, 18, 17, 2))
      expect(adv.keys).not_to include('created_at')
    end

    it 'ordena por recorded_at CRESCENTE' do
      person
      task = nil
      in_workspace(ws) do
        p = Project.create!(name: 'P', position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
        task = create_task(r, desc: 'Fixar', position: 0, status: 'Em Andamento', progress: 60)
      end
      advance!(task, by: person.id, name: 'Ana', to: 60, comment: 'segundo', recorded_at: 1.hour.ago)
      advance!(task, by: person.id, name: 'Ana', to: 30, comment: 'primeiro', recorded_at: 3.hours.ago)

      comments = report['tree'][0]['cells'][0]['robots'][0]['tasks'][0]['advances'].map { |a| a['comment'] }
      expect(comments).to eq(['primeiro', 'segundo'])
    end
  end

  describe 'leitura tolerante e responsáveis (5.2/5.5, D11)' do
    it 'projeto vazio, célula vazia, tarefa sem responsável e sem histórico convivem sem estourar' do
      person
      in_workspace(ws) do
        Project.create!(name: 'Projeto Vazio', position: 0) # sem células
        p2 = Project.create!(name: 'P2', position: 1)
        Cell.create!(project_id: p2.id, name: 'Célula Vazia', position: 0) # sem robôs
        c2 = Cell.create!(project_id: p2.id, name: 'C2', position: 1)
        r = Robot.create!(cell_id: c2.id, name: 'R', application: 'Solda Ponto', position: 0)
        create_task(r, desc: 'Sem responsável, sem histórico', position: 0, status: 'Pendente', progress: 0)
      end

      body = report
      expect(response).to have_http_status(:ok)
      vazio = body['tree'].find { |p| p['name'] == 'Projeto Vazio' }
      expect(vazio['cells']).to eq([])
      expect(vazio['weighted_progress']).to eq(0)
      task = body['tree'].find { |p| p['name'] == 'P2' }['cells'].find { |c| c['name'] == 'C2' }['robots'][0]['tasks'][0]
      expect(task['assignees']).to eq([]) # D11 — nunca "Não Atribuído"
      expect(task['advances']).to eq([])
      expect(body.to_json).not_to include('Não Atribuído')
    end
  end

  describe 'Conclusões e autoria (6.1/6.4, D-R7)' do
    def robot!
      in_workspace(ws) do
        p = Project.create!(name: 'P', position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      end
    end

    it 'ramo 1: autor da entrada de 100 — mesmo que o responsável ATUAL seja outro' do
      person
      bruno = in_workspace(ws) { Person.create!(name: 'Bruno') }
      task = in_workspace(ws) { create_task(robot!, desc: 'Fixar', position: 0, status: 'Concluído', progress: 100) }
      # Ana levou a 100; DEPOIS o responsável vira Bruno
      advance!(task, by: person.id, name: 'Ana', to: 100, from: 90, recorded_at: 2.hours.ago)
      in_workspace(ws) { TaskAssignee.create!(task_id: task.id, person_id: bruno.id, workspace_id: ws.id) }

      c = report['conclusions'].find { |x| x['task_id'] == task.id }
      expect(c['concluded_by']).to eq('Ana')  # o autor da conclusão, não o responsável atual
      expect(c['concluded_at']).to be_present
    end

    it 'reconclusão usa a entrada MAIS RECENTE que chegou a 100' do
      person
      task = in_workspace(ws) { create_task(robot!, desc: 'Fixar', position: 0, status: 'Concluído', progress: 100) }
      advance!(task, by: person.id, name: 'Ana', to: 100, from: 90, recorded_at: 5.hours.ago)   # 1ª vez a 100
      advance!(task, by: person.id, name: 'Carla', to: 60, from: 100, recorded_at: 3.hours.ago)  # caiu
      advance!(task, by: person.id, name: 'Diego', to: 100, from: 60, recorded_at: 1.hour.ago)   # voltou a 100

      c = report['conclusions'].find { |x| x['task_id'] == task.id }
      expect(c['concluded_by']).to eq('Diego') # a última que chegou a 100
    end

    it 'ramo 2: sem entrada de 100 (Concluído direto) usa os responsáveis atuais' do
      person
      task = in_workspace(ws) { create_task(robot!, desc: 'Direto', position: 0, status: 'Concluído', progress: 100) }
      in_workspace(ws) { TaskAssignee.create!(task_id: task.id, person_id: person.id, workspace_id: ws.id) }

      c = report['conclusions'].find { |x| x['task_id'] == task.id }
      expect(c['concluded_by']).to eq('Ana')
      expect(c['concluded_at']).to be_nil
    end

    it 'ramo 3: sem entrada e sem responsável → traço' do
      person
      task = in_workspace(ws) { create_task(robot!, desc: 'Órfã', position: 0, status: 'Concluído', progress: 100) }

      c = report['conclusions'].find { |x| x['task_id'] == task.id }
      expect(c['concluded_by']).to eq('—')
    end

    it 'só tarefas a 100 aparecem (95% ou N/A não entram)' do
      person
      in_workspace(ws) do
        r = robot!
        create_task(r, desc: 'Feita', position: 0, status: 'Concluído', progress: 100)
        create_task(r, desc: 'Quase', position: 1, status: 'Em Andamento', progress: 95)
        create_task(r, desc: 'NA', position: 2, status: 'N/A', progress: 0)
      end
      descs = report['conclusions'].map { |c| c['description'] }
      expect(descs).to eq(['Feita'])
    end
  end
end
