# frozen_string_literal: true

require 'rails_helper'

# hierarchy-soft-delete G2 (§2.9, D3, D4) — a EXCLUSÃO passa a ARQUIVAR. A prova
# central: excluir um robô que tem avanços responde 204 (hoje daria 500, porque a
# FK task_advances→tasks é ON DELETE RESTRICT e a trilha é imutável). O robô some
# da leitura, a trilha fica intacta, e o progresso do pai é recalculado.
RSpec.describe 'Soft-delete da hierarquia (exclusão)', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  # Cria a Person do dono (autor dos avanços) — o bootstrap real só chega no G5.
  def ensure_person(workspace, user)
    in_workspace(workspace) { Person.find_or_create_by!(user_id: user.id) { |p| p.name = user.name } }
  end

  def advance!(workspace, user, task_id, progress)
    in_workspace(workspace) do
      ctx = Authorization::Context.new(user: user, workspace: Workspace.find(workspace.id))
      TaskAdvances::CreateService.new(context: ctx)
        .call(task_id: task_id, id: SecureRandom.uuid, progress: progress, lock_version: 0)
    end
  end

  it 'exclui robô COM avanços: 204, robô arquivado, trilha intacta, célula recalculada' do
    ensure_person(ws, ana)
    ids = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      cell = Cell.create!(project_id: proj.id, name: 'Célula')
      r1 = Robot.create!(cell_id: cell.id, name: 'R-100', position: 0)
      r2 = Robot.create!(cell_id: cell.id, name: 'R-000', position: 1)
      t1 = create_task(r1, desc: 'liga', weight: 1, progress: 0, status: 'Pendente', position: 0)
      create_task(r2, desc: 'espera', weight: 1, progress: 0, status: 'Pendente', position: 0)
      { cell: cell.id, r1: r1.id, r2: r2.id, t1: t1.id }
    end
    advance!(ws, ana, ids[:t1], 100) # r1 → 100; célula = média(100, 0) = 50

    expect(in_workspace(ws) { Cell.find(ids[:cell]).progress_cache }).to eq(50)
    avancos_antes = in_workspace(ws) { TaskAdvance.unscoped.where(task_id: ids[:t1]).count }
    expect(avancos_antes).to be_positive

    delete "/api/v1/robots/#{ids[:r1]}", headers: headers(ana)
    expect(response).to have_http_status(:no_content)

    in_workspace(ws) do
      expect(Robot.where(id: ids[:r1])).to be_empty                       # some da leitura
      expect(Robot.unscoped.find(ids[:r1]).deleted_at).to be_present      # arquivado
      expect(TaskAdvance.unscoped.where(task_id: ids[:t1]).count).to eq(avancos_antes) # trilha intacta
      expect(Task.unscoped.find(ids[:t1]).deleted_at).to be_present       # tarefa arquivada junto
      expect(Cell.find(ids[:cell]).progress_cache).to eq(0)               # recalculado (só R-000 vivo, a 0)
    end

    get '/api/v1/robots', params: { cell_id: ids[:cell] }, headers: headers(ana)
    nomes = JSON.parse(response.body).map { |r| r['name'] }
    expect(nomes).to contain_exactly('R-000')
  end

  it 'excluir projeto arquiva a subárvore inteira, sem apagar avanço' do
    ensure_person(ws, ana)
    ids = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      cell = Cell.create!(project_id: proj.id, name: 'Célula')
      robo = Robot.create!(cell_id: cell.id, name: 'R', position: 0)
      task = create_task(robo, desc: 'liga', weight: 1, progress: 0, status: 'Pendente', position: 0)
      { proj: proj.id, cell: cell.id, robot: robo.id, task: task.id }
    end
    advance!(ws, ana, ids[:task], 100) # avanço a 100 não exige comentário (§2.2)

    delete "/api/v1/projects/#{ids[:proj]}", headers: headers(ana)
    expect(response).to have_http_status(:no_content)

    in_workspace(ws) do
      expect(Project.where(id: ids[:proj])).to be_empty
      expect(Cell.where(id: ids[:cell])).to be_empty
      expect(Robot.where(id: ids[:robot])).to be_empty
      expect(Task.where(id: ids[:task])).to be_empty
      expect(Robot.unscoped.find(ids[:robot]).deleted_at).to be_present
      expect(TaskAdvance.unscoped.where(task_id: ids[:task]).count).to be_positive
    end
  end

  it 'exclusão cross-tenant responde 404 e NÃO arquiva a linha alheia' do
    robo_b = in_workspace(ws_b) do
      proj = Project.create!(name: 'Linha B')
      cell = Cell.create!(project_id: proj.id, name: 'Célula B')
      Robot.create!(cell_id: cell.id, name: 'R-B', position: 0).id
    end

    delete "/api/v1/robots/#{robo_b}", headers: headers(ana) # sessão de A mira robô de B
    expect(response).to have_http_status(:not_found)

    in_workspace(ws_b) do
      expect(Robot.unscoped.find(robo_b).deleted_at).to be_nil # intacto
    end
  end
end
