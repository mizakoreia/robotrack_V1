# frozen_string_literal: true

require 'rails_helper'

# progress-advances 3.1–3.6 (§2.4, D-ID, D-409, D-TS, D-AUTO) — a transação do
# registro de avanço, provada no nível do service (as negações por HTTP — 403/404
# — ficam no request spec do G4).
RSpec.describe TaskAdvances::CreateService, :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  # Cria a Person do ator (make_workspace não semeia) e monta o contexto.
  let(:setup) do
    in_workspace(ws) do
      pessoa = Person.create!(name: 'Ana Dona', user_id: ana.id)
      projeto = Project.create!(name: 'L')
      celula = Cell.create!(project_id: projeto.id, name: 'C')
      robo = Robot.create!(cell_id: celula.id, name: 'R')
      tarefa = create_task(robo, desc: 'Power On', progress: 45, status: 'Em Andamento', position: 0)
      { pessoa: pessoa, tarefa: tarefa, robo: robo }
    end
  end

  def context
    in_workspace(ws) { Authorization::Context.new(user: ana, workspace: Workspace.find(ws.id)) }
  end

  def call(**kwargs)
    in_workspace(ws) { described_class.new(context: context).call(**kwargs) }
  end

  def advances_count(task_id)
    in_workspace(ws) { TaskAdvance.where(task_id: task_id).count }
  end

  describe 'a regra dura do comentário (§2.4 item 3)' do
    it '45 → 100 sem comentário: 201, tarefa Concluído/100' do
      s = setup
      r = call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0)
      expect(r[:status]).to eq(201)
      t = in_workspace(ws) { Task.find(s[:tarefa].id) }
      expect([t.status, t.progress]).to eq(['Concluído', 100])
    end

    it '45 → 60 sem comentário: 422 e NENHUMA linha criada, tarefa intacta' do
      s = setup
      r = call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 60, lock_version: 0)
      expect(r[:status]).to eq(422)
      expect(advances_count(s[:tarefa].id)).to eq(0)
      t = in_workspace(ws) { Task.find(s[:tarefa].id) }
      expect([t.status, t.progress]).to eq(['Em Andamento', 45])
    end

    it '45 → 60 COM comentário: 201, Em Andamento/60' do
      s = setup
      r = call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 60, comment: 'faltou aterrar', lock_version: 0)
      expect(r[:status]).to eq(201)
      t = in_workspace(ws) { Task.find(s[:tarefa].id) }
      expect([t.status, t.progress]).to eq(['Em Andamento', 60])
    end
  end

  describe 'clamp de recorded_at (D-TS)' do
    it 'futuro além do skew é clampado, com recorded_at_adjusted' do
      s = setup
      r = call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100,
               recorded_at: 3.days.from_now.iso8601, lock_version: 0)
      adv = r[:data][:advance]
      expect(adv.recorded_at_adjusted).to be(true)
      expect(adv.recorded_at).to be <= Time.current + 1.minute
    end

    it 'recorded_at ausente usa now(), sem ajuste' do
      s = setup
      r = call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0)
      expect(r[:data][:advance].recorded_at_adjusted).to be(false)
    end
  end

  describe 'auto-atribuição (D-AUTO)' do
    it 'tarefa sem responsável ganha o autor' do
      s = setup
      call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0)
      nomes = in_workspace(ws) { Task.find(s[:tarefa].id).assignees.map(&:name) }
      expect(nomes).to eq(['Ana Dona'])
    end

    it 'tarefa com responsável (Bruno) NÃO é reatribuída' do
      s = setup
      bruno_p = in_workspace(ws) { Person.create!(name: 'Bruno') }
      in_workspace(ws) { TaskAssignee.create!(task_id: s[:tarefa].id, person_id: bruno_p.id, workspace_id: ws.id) }

      call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0)
      nomes = in_workspace(ws) { Task.find(s[:tarefa].id).assignees.map(&:name) }
      expect(nomes).to eq(['Bruno'])
    end
  end

  describe 'idempotência e conflito (D-ID/D-409)' do
    it 'reenviar o MESMO uuid: 200 replay, uma única entrada, sem 409' do
      s = setup
      uuid = SecureRandom.uuid
      r1 = call(task_id: s[:tarefa].id, id: uuid, progress: 100, lock_version: 0)
      # lock_version já subiu para 1; o retry manda o MESMO uuid E o lock_version
      # velho (0) — a idempotência tem de vencer ANTES do check de versão.
      r2 = call(task_id: s[:tarefa].id, id: uuid, progress: 100, lock_version: 0)
      expect([r1[:status], r2[:status]]).to eq([201, 200])
      expect(r2[:data][:replay]).to be(true)
      expect(advances_count(s[:tarefa].id)).to eq(1)
    end

    it 'lock_version divergente (uuid novo): 409 com o estado atual, sem entrada' do
      s = setup
      call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 60, comment: 'x', lock_version: 0) # sobe p/ 1
      r = call(task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 80, comment: 'y', lock_version: 0) # stale
      expect(r[:status]).to eq(409)
      expect(r[:error]).to eq('conflito_de_versao')
      expect(r[:details][:task][:progress]).to eq(60)
      expect(advances_count(s[:tarefa].id)).to eq(1)
    end
  end

  describe 'concorrência (§2.4 item 4 / D-409)' do
    it 'duas sessões com o mesmo lock_version: uma 201, a outra 409; uma única entrada' do
      s = setup
      results = []
      threads = Array.new(2) do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Tenant.with(workspace_id: ws.id, user_id: ana.id) do
              ctx = Authorization::Context.new(user: ana, workspace: Workspace.find(ws.id))
              results << described_class.new(context: ctx).call(
                task_id: s[:tarefa].id, id: SecureRandom.uuid, progress: 100, lock_version: 0
              )[:status]
            end
          rescue StandardError => e
            results << e.class.name
          end
        end
      end
      threads.each(&:join)

      expect(results.sort).to eq([201, 409])
      expect(advances_count(s[:tarefa].id)).to eq(1)
    end
  end
end
