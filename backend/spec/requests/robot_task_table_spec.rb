# frozen_string_literal: true

require 'rails_helper'

# robot-task-table 1.1/1.2/1.6 (§3.5, D-RTT-3/4, D8) — o contrato agregado da tabela
# do robô: assignees vs contributors SEPARADOS, `last_advance` por `recorded_at`
# (nunca `created_at`), `advances_count` inclui legacy, custo CONSTANTE em N (sem
# N+1) e isolamento cross-tenant (404 via RLS).
RSpec.describe 'Tabela do robô — GET /api/v1/robots/:id/tasks', :tenancy, type: :request do
  let(:ana)  { create(:user, name: 'Ana Dona') }
  let(:ws)   { make_workspace(owner: ana) }

  def headers = auth_headers(ana).merge('X-Workspace-Id' => ws.id)

  def make_robot
    in_workspace(ws) do
      p = Project.create!(name: 'P')
      c = Cell.create!(project_id: p.id, name: 'C')
      Robot.create!(cell_id: c.id, name: 'R01', application: 'Solda Ponto')
    end
  end

  def advance!(task, by:, name:, to:, comment: 'ok', legacy: false, recorded_at: Time.current)
    TaskAdvance.create!(
      task_id: task.id, workspace_id: ws.id, by: by, author_name_snapshot: name,
      from_progress: 0, to_progress: to, comment: comment, legacy: legacy, recorded_at: recorded_at
    )
  end

  describe 'contrato (D-RTT-4, D8)' do
    it 'assignees e contributors são conjuntos separados; last_advance por recorded_at' do
      robot = make_robot
      body = in_workspace(ws) do
        anaP = Person.create!(name: 'Ana', user_id: ana.id)
        brunoP = Person.create!(name: 'Bruno')
        task = create_task(robot, desc: 'T1', weight: 1, progress: 40, status: 'Em Andamento', position: 0)
        TaskAssignee.create!(task_id: task.id, person_id: anaP.id, workspace_id: ws.id) # Ana = responsável
        # Bruno registrou avanço (contribuidor, NÃO responsável); recorded_at antigo mas created_at novo
        advance!(task, by: brunoP.id, name: 'Bruno', to: 40, comment: 'meio', recorded_at: 2.hours.ago)
        advance!(task, by: nil, name: 'Import', to: 20, comment: nil, legacy: true, recorded_at: 3.hours.ago)
        nil
      end
      get "/api/v1/robots/#{robot.id}/tasks", headers: headers
      expect(response).to have_http_status(:ok)
      row = JSON.parse(response.body).first

      expect(row['assignees'].map { |a| a['name'] }).to eq(['Ana'])
      expect(row['contributors'].map { |c| c['name'] }).to eq(['Bruno']) # Ana não avançou; legacy sem autor não entra
      expect(row['advances_count']).to eq(2) # inclui a legacy
      # último por recorded_at (o de Bruno, 2h atrás) — não o legacy (3h atrás)
      expect(row['last_advance']).to include('recorded_at', 'author_name_snapshot' => 'Bruno', 'legacy' => false)
      expect(row['last_advance']).not_to have_key('created_at') # D8 — nunca vaza created_at
    end
  end

  describe 'orçamento de query CONSTANTE em N (sem N+1)' do
    it '40 tarefas custam o MESMO número de queries que 1 (constante em N)' do
      robot = make_robot

      def count_queries(headers, robot_id)
        n = 0
        sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
          n += 1 if p[:sql] =~ /\A\s*SELECT/i && p[:name] !~ /SCHEMA/i
        end
        get "/api/v1/robots/#{robot_id}/tasks", headers: headers
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end

      in_workspace(ws) { create_task(robot, desc: 'só uma', weight: 1, progress: 0, status: 'Pendente', position: 0) }
      um = count_queries(headers, robot.id)

      in_workspace(ws) do
        39.times { |i| create_task(robot, desc: "t#{i}", weight: 1, progress: 0, status: 'Pendente', position: i + 1) }
      end
      quarenta = count_queries(headers, robot.id)

      expect(quarenta).to eq(um) # constante: nenhuma query por linha
    end
  end

  describe 'isolamento cross-tenant (1.6, §4.1)' do
    let(:bob) { create(:user, name: 'Bob') }
    let(:w2)  { make_workspace(owner: bob) }

    it 'robô de W2 pedido por usuário de W1 devolve 404 sem vazar o nome' do
      w2_robot = in_workspace(w2) do
        p = Project.create!(name: 'P2'); c = Cell.create!(project_id: p.id, name: 'C2')
        Robot.create!(cell_id: c.id, name: 'ROBO SECRETO W2', application: 'Handling')
      end
      get "/api/v1/robots/#{w2_robot.id}/tasks", headers: headers # headers = W1
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('SECRETO')
    end
  end
end
