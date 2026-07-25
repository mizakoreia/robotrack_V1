# frozen_string_literal: true

require 'rails_helper'

# robot-task-grouping G2 (D-TG-6/7) — exclusão em LOTE de tarefas.
# Owner-only, soft-delete atômico, um recálculo de rollup por robô, trilha
# preservada, e isolamento por tenant (ids invisíveis ignorados).
RSpec.describe 'API de exclusão em lote de tarefas', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def robot_in(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      Robot.create!(cell_id: celula.id, name: 'R-01')
    end
  end

  before { add_member(ws, bruno, 'edit') }

  it 'o DONO exclui várias de uma vez (200 deletedCount) e o rollup do robô recalcula' do
    robo = robot_in(ws)
    fica = in_workspace(ws) { create_task(robo, desc: 'Fica', status: 'Concluído', progress: 100, weight: 1, position: 0) }
    sai1 = in_workspace(ws) { create_task(robo, desc: 'Sai 1', status: 'Pendente', progress: 0, weight: 1, position: 1) }
    sai2 = in_workspace(ws) { create_task(robo, desc: 'Sai 2', status: 'Pendente', progress: 0, weight: 1, position: 2) }

    delete '/api/v1/tasks', params: { ids: [sai1.id, sai2.id] }, headers: headers(ana)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['deletedCount']).to eq(2)
    # só a "Fica" resta → ponderado 100 (o cache recalculou ignorando as excluídas)
    expect(in_workspace(ws) { Task.where(robot_id: robo.id).count }).to eq(1)
    expect(in_workspace(ws) { Task.exists?(fica.id) }).to be(true)
    expect(in_workspace(ws) { Robot.find(robo.id).progress_cache }).to eq(100)
  end

  it 'é SOFT-delete e preserva a trilha de avanços da tarefa excluída' do
    robo = robot_in(ws)
    alvo = in_workspace(ws) { create_task(robo, desc: 'Com avanço', status: 'Pendente', progress: 0, position: 0) }
    # o avanço é registrado por bruno (edit — tem Person no workspace); a exclusão
    # em lote depois é do dono.
    post "/api/v1/tasks/#{alvo.id}/advances",
         params: { id: SecureRandom.uuid, progress: 20, comment: 'energizado', lock_version: 0 },
         headers: headers(bruno)
    expect(response).to have_http_status(:created)
    expect(in_workspace(ws) { TaskAdvance.where(task_id: alvo.id).count }).to eq(1)

    delete '/api/v1/tasks', params: { ids: [alvo.id] }, headers: headers(ana)
    expect(response).to have_http_status(:ok)

    # some da leitura, mas a linha continua no banco com deleted_at (não foi hard delete)
    expect(in_workspace(ws) { Task.exists?(alvo.id) }).to be(false)
    expect(in_workspace(ws) { Task.unscoped.where(id: alvo.id).where.not(deleted_at: nil).exists? }).to be(true)
    # trilha imutável preservada (FK RESTRICT)
    expect(in_workspace(ws) { TaskAdvance.where(task_id: alvo.id).count }).to eq(1)
  end

  it 'um membro edit recebe 403 e nada é excluído (owner-only)' do
    robo = robot_in(ws)
    t = in_workspace(ws) { create_task(robo, desc: 'Intocável por edit') }

    delete '/api/v1/tasks', params: { ids: [t.id] }, headers: headers(bruno)

    expect(response).to have_http_status(:forbidden)
    expect(in_workspace(ws) { Task.exists?(t.id) }).to be(true)
  end

  it 'ignora id de outro tenant (deletedCount conta só o visível; o alheio fica intacto)' do
    robo = robot_in(ws)
    meu = in_workspace(ws) { create_task(robo, desc: 'Meu') }
    robo_b = robot_in(ws_b)
    alheio = in_workspace(ws_b) { create_task(robo_b, desc: 'Alheio') }

    delete '/api/v1/tasks', params: { ids: [meu.id, alheio.id] }, headers: headers(ana)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['deletedCount']).to eq(1)
    expect(in_workspace(ws) { Task.exists?(meu.id) }).to be(false)
    expect(in_workspace(ws_b) { Task.exists?(alheio.id) }).to be(true)
  end
end
