# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 2.7 (§2.1, §2.4, D5.b) — a cascata ponta a ponta: um avanço
# 0 → 100 atualiza os três níveis NO MESMO COMMIT; um 409 reverte tudo; e uma
# leitura concorrente não enxerga o cache novo antes do commit.
RSpec.describe 'Cascata do progresso ponta a ponta', :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  let(:seed) do
    in_workspace(ws) do
      Person.create!(name: 'Ana Dona', user_id: ana.id)
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      robo = Robot.create!(cell_id: celula.id, name: 'R')
      tarefa = create_task(robo, desc: 'Power On', weight: 1, progress: 0, status: 'Pendente', position: 0)
      { project: projeto.id, cell: celula.id, robot: robo.id, task: tarefa.id }
    end
  end

  def context
    in_workspace(ws) { Authorization::Context.new(user: ana, workspace: Workspace.find(ws.id)) }
  end

  def caches(ids)
    in_workspace(ws) do
      [Robot.find(ids[:robot]).progress_cache,
       Cell.find(ids[:cell]).progress_cache,
       Project.find(ids[:project]).progress_cache]
    end
  end

  it 'avanço 0 → 100 atualiza robô, célula e projeto no mesmo commit' do
    ids = seed
    in_workspace(ws) do
      TaskAdvances::CreateService.new(context: context)
        .call(task_id: ids[:task], id: SecureRandom.uuid, progress: 100, lock_version: 0)
    end
    expect(caches(ids)).to eq([100, 100, 100])
  end

  it 'avanço que falha por 409 (lock_version stale) não adianta o cache' do
    ids = seed
    # sobe para 60 (cache 60/60/60)
    in_workspace(ws) do
      TaskAdvances::CreateService.new(context: context)
        .call(task_id: ids[:task], id: SecureRandom.uuid, progress: 60, comment: 'x', lock_version: 0)
    end
    expect(caches(ids)).to eq([60, 60, 60])

    # tentativa com lock_version velho → 409, cache permanece 60
    r = in_workspace(ws) do
      TaskAdvances::CreateService.new(context: context)
        .call(task_id: ids[:task], id: SecureRandom.uuid, progress: 100, lock_version: 0)
    end
    expect(r[:status]).to eq(409)
    expect(caches(ids)).to eq([60, 60, 60])
  end

  it 'leitura concorrente não enxerga o cache novo antes do commit' do
    ids = seed
    entrou = Queue.new
    libera = Queue.new

    writer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Tenant.with(workspace_id: ws.id, user_id: ana.id) do
          ActiveRecord::Base.transaction do
            ctx = Authorization::Context.new(user: ana, workspace: Workspace.find(ws.id))
            TaskAdvances::CreateService.new(context: ctx)
              .call(task_id: ids[:task], id: SecureRandom.uuid, progress: 100, lock_version: 0)
            entrou.push(:escrito)  # escrito, ainda não commitado
            libera.pop             # espera o leitor
          end
        end
      end
    end

    entrou.pop
    visto = ActiveRecord::Base.connection_pool.with_connection do
      Tenant.with(workspace_id: ws.id, user_id: ana.id) { Robot.find(ids[:robot]).progress_cache }
    end
    libera.push(:vai)
    writer.join

    expect(visto).to eq(0) # READ COMMITTED: não vê o 100 não-commitado
    expect(in_workspace(ws) { Robot.find(ids[:robot]).progress_cache }).to eq(100)
  end
end
