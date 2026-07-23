# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 3.5 — publicação AGREGADA das operações em massa: um
# único envelope terminal em vez de N por linha. O lote de robôs usa `insert_all`
# (sem callback), então não há `robot.created` por linha para suprimir — o
# agregado é um publish ADICIONAL, disparado pós-commit por `Realtime.after_commit`.
RSpec.describe 'Publicação agregada (3.5)', :tenancy do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws) { make_workspace(owner: owner) }
  let(:captured) { [] }

  before do
    Realtime::PublisherService.reset_failure_count!
    Current.user_id = owner.id
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| captured << { stream:, payload: } }
  end

  after { Current.reset }

  it 'lote de 50 robôs publica 1 robot.batch_created, não 50 robot.created' do
    ancestors = {}
    Realtime.suppress do
      in_workspace(ws) do
        project = Project.create!(name: 'Linha')
        cell = Cell.create!(project_id: project.id, name: 'Célula')
        ancestors = { project: project.id, cell: cell.id }
      end
    end
    captured.clear

    robots = Array.new(50) { |i| { name: "R-#{format('%03d', i)}" } }
    in_workspace(ws) do
      Robots::BatchCreateService.new(context: nil).call(
        cell_id: ancestors[:cell], application: 'Handling', robots:
      )
    end

    expect(captured.map { |c| c[:payload]['type'] }).to eq(['robot.batch_created'])
    env = captured.first[:payload]
    expect(env['scope']).to eq({ 'project_id' => ancestors[:project], 'cell_id' => ancestors[:cell] })
    expect(env['entity']).to be_nil
    expect(env['seq']).to be_a(Integer)
    expect(captured.first[:stream]).to eq("ws:#{ws.id}:v1")
  end
end
