# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 3.2/3.6 — a publicação pós-commit: envelope PONTEIRO,
# `seq` monotônico reservado no `after_commit` (reabrindo o tenant, porque o SET
# LOCAL da request já morreu no COMMIT), transação abortada não consome número, e
# falha de broadcast (Redis) nunca derruba a mutação.
#
# Broadcast é stubbado para capturar o envelope diretamente (o que o publisher
# entrega ao Cable), sem depender do adapter de teste.
RSpec.describe Realtime::PublisherService, :tenancy do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws) { make_workspace(owner: owner) }
  let(:captured) { [] }

  before do
    described_class.reset_failure_count!
    Current.user_id = owner.id
    Current.origin_id = nil
    Current.actor_person_id = nil
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| captured << { stream:, payload: } }
  end

  after { Current.reset }

  # Cria a hierarquia SEM emitir evento (o teste mede só a mutação sob exame).
  def build_hierarchy
    ids = {}
    Realtime.suppress do
      in_workspace(ws) do
        project = Project.create!(name: 'Linha')
        cell = Cell.create!(project_id: project.id, name: 'Célula')
        robot = Robot.create!(cell_id: cell.id, name: 'R-100', position: 0)
        task = create_task(robot, desc: 'Fixar base', weight: 1, position: 0)
        ids = { project: project.id, cell: cell.id, robot: robot.id, task: task.id }
      end
    end
    ids
  end

  it 'publica task_advance.created após commit: entity=task e scope dos 3 ancestrais' do
    h = build_hierarchy
    person = in_workspace(ws) { Person.create!(name: 'Ana', email: 'ana@x.com', user_id: owner.id) }
    captured.clear

    in_workspace(ws) do
      TaskAdvance.create!(
        task_id: h[:task], by: person.id, author_name_snapshot: 'Ana',
        recorded_at: Time.current, from_progress: 0, to_progress: 60, comment: 'subiu'
      )
    end

    advances = captured.select { |c| c[:payload]['type'] == 'task_advance.created' }
    expect(advances.size).to eq(1)
    expect(advances.first[:stream]).to eq("ws:#{ws.id}:v1")
    env = advances.first[:payload]
    expect(env['entity']).to eq({ 'kind' => 'task', 'id' => h[:task] })
    expect(env['scope']).to eq({ 'project_id' => h[:project], 'cell_id' => h[:cell], 'robot_id' => h[:robot] })
    expect(env['workspace_id']).to eq(ws.id)
    expect(env['v']).to eq(1)
    expect(env['seq']).to be_a(Integer)
  end

  it 'transação revertida não publica' do
    in_workspace(ws) do
      ActiveRecord::Base.transaction(requires_new: true) do
        Project.create!(name: 'some')
        raise ActiveRecord::Rollback
      end
    end

    expect(captured).to be_empty
  end

  it 'seq é estritamente crescente na ordem de emissão' do
    seqs = Array.new(3) do |i|
      in_workspace(ws) { Project.create!(name: "P#{i}") }
      captured.last[:payload]['seq']
    end

    expect(seqs).to eq([1, 2, 3])
  end

  it 'seq não é consumido por transação abortada' do
    in_workspace(ws) { Project.create!(name: 'ok-1') }
    in_workspace(ws) do
      ActiveRecord::Base.transaction(requires_new: true) do
        Project.create!(name: 'reverte')
        raise ActiveRecord::Rollback
      end
    end
    in_workspace(ws) { Project.create!(name: 'ok-2') }

    expect(captured.map { |c| c[:payload]['seq'] }).to eq([1, 2])
  end

  it 'sequências de workspaces distintos são independentes' do
    ws2 = make_workspace(owner: create(:user, name: 'Bob'))
    in_workspace(ws)  { Project.create!(name: 'A') }
    in_workspace(ws)  { Project.create!(name: 'B') }
    in_workspace(ws2) { Project.create!(name: 'C') }

    last = captured.last[:payload]
    expect(last['workspace_id']).to eq(ws2.id)
    expect(last['seq']).to eq(1)
    expect(captured[0..1].map { |c| c[:payload]['seq'] }).to eq([1, 2])
  end

  it 'envelope é ponteiro: não transporta conteúdo da entidade' do
    h = build_hierarchy
    captured.clear
    robot = in_workspace(ws) { Robot.find(h[:robot]) }

    in_workspace(ws) { create_task(robot, desc: 'TEXTO-SECRETO-DA-TAREFA', weight: 1, position: 1) }

    env = captured.last[:payload]
    expect(env.keys).to contain_exactly(
      'v', 'seq', 'workspace_id', 'type', 'entity', 'scope', 'actor_person_id', 'origin_id', 'at'
    )
    expect(env.to_json).not_to include('TEXTO-SECRETO')
  end

  it 'falha de broadcast (Redis) não derruba a mutação e incrementa o contador' do
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError.new('redis down'))

    expect { in_workspace(ws) { Project.create!(name: 'sobrevive') } }.not_to raise_error
    expect(described_class.failure_count).to be >= 1
    # a linha commitou apesar da falha de publicação
    expect(in_workspace(ws) { Project.where(name: 'sobrevive').exists? }).to be(true)
  end
end
