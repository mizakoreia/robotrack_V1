# frozen_string_literal: true

require 'rails_helper'

# task-catalog 5.5–5.7 (§2.6, §4.1, D-TC-6) — a sincronização retroativa: aplica
# ao robô os templates que faltam, sem sobrescrever, com contagem honesta,
# isolada por tenant e autorizada.
RSpec.describe 'Sincronização retroativa de tarefas-base', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def seed_catalog(workspace)
    in_workspace(workspace) { Workspaces::SeedDefaultTaskTemplatesService.new(workspace_id: workspace.id).call }
  end

  def robot(workspace, application, name: 'R')
    in_workspace(workspace) do
      projeto = Project.create!(name: 'L')
      celula = Cell.create!(project_id: projeto.id, name: 'C')
      Robot.create!(cell_id: celula.id, name: name, application: application)
    end
  end

  def sync(robot_id, as: bruno, workspace: ws)
    post "/api/v1/robots/#{robot_id}/sync_task_templates", headers: headers(as, workspace)
  end

  def descs(robot_id, workspace = ws)
    in_workspace(workspace) { Task.where(robot_id: robot_id).pluck(:desc) }
  end

  before do
    add_member(ws, bruno, 'edit')
    add_member(ws, clara, 'view')
    seed_catalog(ws)
  end

  describe 'aplicabilidade concreta (5.5)' do
    it 'Handling com TCP Check(60) recebe 29 (com Check sinais de Gripper), preserva TCP Check e pula Calibração de Cola' do
      robo = robot(ws, 'Handling')
      in_workspace(ws) { create_task(robo, desc: 'TCP Check', progress: 60, position: 0) }

      sync(robo.id)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['addedCount']).to eq(29)

      d = descs(robo.id)
      expect(d.size).to eq(30)
      expect(d).to include('Check sinais de Gripper')
      expect(d).not_to include('Calibração de Cola')
      tcp = in_workspace(ws) { Task.find_by(robot_id: robo.id, desc: 'TCP Check') }
      expect([tcp.progress, tcp.position]).to eq([60, 0])
    end

    it 'Solda MIG do zero recebe 29, sem Calibração de Cola nem Check sinais de Gripper, zeradas' do
      robo = robot(ws, 'Solda MIG')
      sync(robo.id)
      expect(JSON.parse(response.body)['addedCount']).to eq(29)

      in_workspace(ws) do
        tarefas = Task.where(robot_id: robo.id)
        expect(tarefas.pluck(:desc)).not_to include('Calibração de Cola', 'Check sinais de Gripper')
        expect(tarefas.pluck(:progress).uniq).to eq([0])
        expect(tarefas.pluck(:status).uniq).to eq(['Pendente'])
        expect(tarefas.all? { |t| t.assignees.empty? }).to be(true)
        # weight vem do template de origem (todos 1 no catálogo padrão).
        expect(tarefas.pluck(:weight).map(&:to_i).uniq).to eq([1])
      end
    end

    it 'as novas entram ao fim da ordem (positions 1..29 após a existente em 0)' do
      robo = robot(ws, 'Solda MIG')
      in_workspace(ws) { create_task(robo, desc: 'Power On', position: 0) }
      sync(robo.id)

      posicoes = in_workspace(ws) { Task.where(robot_id: robo.id).order(:position).pluck(:position) }
      expect(posicoes).to eq((0..28).to_a) # 0 (existente) + 1..28 (28 novas; Power On já existia)
    end
  end

  describe 'nunca sobrescreve (5.6)' do
    it 'preserva progresso/status/responsável de tarefa existente e não a duplica' do
      robo = robot(ws, 'Handling')
      in_workspace(ws) do
        tarefa = create_task(robo, desc: 'Power On', progress: 100, status: 'Concluído', position: 0)
        TaskAssignee.create!(task: tarefa, person: Person.create!(name: 'Ana Resp'))
      end

      sync(robo.id)

      in_workspace(ws) do
        power = Task.where(robot_id: robo.id, desc: 'Power On')
        expect(power.count).to eq(1)
        t = power.first
        expect([t.progress, t.status]).to eq([100, 'Concluído'])
        expect(t.assignees.map(&:name)).to eq(['Ana Resp'])
      end
    end

    it 'comparação de desc ignora caixa e espaços: "tcp check " bloqueia "TCP Check"' do
      robo = robot(ws, 'Solda MIG')
      in_workspace(ws) { create_task(robo, desc: 'tcp check ', position: 0) }
      sync(robo.id)

      d = descs(robo.id)
      expect(d.count { |x| x.strip.downcase == 'tcp check' }).to eq(1)
    end

    it 'tarefa criada à mão (Speed up) bloqueia o template de mesmo nome' do
      robo = robot(ws, 'Solda MIG')
      in_workspace(ws) { create_task(robo, desc: 'Speed up', progress: 40, position: 0) }
      sync(robo.id)

      in_workspace(ws) do
        speed = Task.where(robot_id: robo.id, desc: 'Speed up')
        expect(speed.count).to eq(1)
        expect(speed.first.progress).to eq(40)
      end
    end

    it 'sincronizar duas vezes: a segunda informa 0 e o total não muda' do
      robo = robot(ws, 'Solda MIG')
      sync(robo.id)
      primeiro = JSON.parse(response.body)['addedCount']
      sync(robo.id)
      segundo = JSON.parse(response.body)['addedCount']

      expect([primeiro, segundo]).to eq([29, 0])
      expect(descs(robo.id).size).to eq(29)
    end
  end

  describe 'contagem honesta (5.3)' do
    it 'reflete só o inserido: Handling com TCP Check e Power On responde 28 (2→30)' do
      robo = robot(ws, 'Handling')
      in_workspace(ws) do
        create_task(robo, desc: 'TCP Check', position: 0)
        create_task(robo, desc: 'Power On', position: 1)
      end
      sync(robo.id)
      expect(JSON.parse(response.body)['addedCount']).to eq(28)
      expect(descs(robo.id).size).to eq(30)
    end

    it 'catálogo sem template aplicável informa 0' do
      robo = robot(ws, 'Outros')
      in_workspace(ws) do
        TaskTemplate.delete_all
        TaskTemplate.create!(cat: 'X. Cola', desc: 'Só Sealing', app_filters: ['Sealing'])
      end
      sync(robo.id)
      expect(JSON.parse(response.body)['addedCount']).to eq(0)
      expect(descs(robo.id)).to eq([])
    end

    it 'falha no meio reverte por inteiro e não deixa contagem parcial' do
      robo = robot(ws, 'Solda MIG')
      allow(Task).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, 'boom')
      sync(robo.id)
      expect(response.status).to be >= 400
      expect(descs(robo.id)).to eq([])
    end
  end

  describe 'autorização e isolamento (5.4)' do
    it 'view recebe 403 e o número de tarefas não muda' do
      robo = robot(ws, 'Solda MIG')
      sync(robo.id, as: clara)
      expect(response).to have_http_status(:forbidden)
      expect(descs(robo.id)).to eq([])
    end

    it 'robô de outro workspace responde 404, sem criar tarefa' do
      robo_b = robot(ws_b, 'Solda MIG')
      sync(robo_b.id, as: ana, workspace: ws)
      expect(response).to have_http_status(:not_found)
      expect(descs(robo_b.id, ws_b)).to eq([])
    end

    it 'usa o catálogo do workspace DO ROBÔ (não vaza template de outro workspace)' do
      # ws (A) tem "Check de aterramento"; ws_b não tem. Robô de B não o recebe.
      in_workspace(ws) { TaskTemplate.create!(cat: 'J. Elétrica', desc: 'Check de aterramento') }
      seed_catalog(ws_b)
      robo_b = robot(ws_b, 'Solda MIG')

      sync(robo_b.id, as: diego, workspace: ws_b)
      expect(response).to have_http_status(:ok)
      expect(descs(robo_b.id, ws_b)).not_to include('Check de aterramento')
    end
  end

  describe 'concorrência (5.7) — nível de service' do
    it 'duas syncs simultâneas do mesmo robô terminam com 29, nunca 58' do
      robo = robot(ws, 'Solda MIG')
      errors = []
      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Tenant.with(workspace_id: ws.id, user_id: ana.id) do
              TaskTemplates::SyncToRobotService.new(context: nil).call(robot_id: robo.id)
            end
          rescue StandardError => e
            errors << e
          end
        end
      end
      threads.each(&:join)

      total = in_workspace(ws) { Task.where(robot_id: robo.id).count }
      expect(total).to eq(29), "esperado 29 tarefas, veio #{total} (erros: #{errors.map(&:message)})"
    end
  end
end
