# frozen_string_literal: true

require 'rails_helper'

# progress-advances 6.4 (§2.4 item 4, D-AUTO/D6/D-RT-7) — o teste ponta a ponta:
# UMA confirmação de avanço `0 → 20` numa tarefa sem responsável produz os CINCO
# efeitos na mesma transação, e o evento é publicado UMA única vez.
#
# É a prova de integração que os specs de unidade não dão: cada um cobre um
# efeito; este exige que os cinco aconteçam juntos, pela porta HTTP real, e que a
# notificação (D6, pós-commit) não dispare duas vezes.
RSpec.describe 'Fluxo ponta a ponta do avanço', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }

  def headers(user)
    auth_headers(user).merge('X-Workspace-Id' => ws.id)
  end

  before { add_member(ws, bruno, 'edit') } # bruno ganha Person (será o autor)

  it 'avanço 0 → 20 em tarefa sem responsável: trilha, transição, auto-atribuição, lock_version e evento único' do
    tarefa = in_workspace(ws) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      robo = Robot.create!(cell_id: celula.id, name: 'R-01')
      create_task(robo, desc: 'Power On', progress: 0, status: 'Pendente', position: 0)
    end

    eventos = []
    assinatura = ActiveSupport::Notifications.subscribe('task.advanced') do |*args|
      eventos << ActiveSupport::Notifications::Event.new(*args)
    end

    begin
      post "/api/v1/tasks/#{tarefa.id}/advances",
           params: { id: SecureRandom.uuid, progress: 20, comment: 'energizado', lock_version: 0 },
           headers: headers(bruno)
    ensure
      ActiveSupport::Notifications.unsubscribe(assinatura)
    end

    expect(response).to have_http_status(:created)

    recarregada, avancos, responsaveis, autor = in_workspace(ws) do
      t = Task.find(tarefa.id)
      [t, TaskAdvance.where(task_id: t.id).to_a, t.assignees.map(&:name), Person.find_by(user_id: bruno.id)]
    end

    # 1. entrada na trilha (0 → 20)
    expect(avancos.size).to eq(1)
    expect([avancos.first.from_progress, avancos.first.to_progress]).to eq([0, 20])
    expect(avancos.first.author_name_snapshot).to eq('Bruno Edit')

    # 2. transição Pendente → Em Andamento, progress 20
    expect([recarregada.status, recarregada.progress]).to eq(['Em Andamento', 20])

    # 3. auto-atribuição do autor (tarefa não tinha responsável)
    expect(responsaveis).to eq(['Bruno Edit'])
    expect(avancos.first.by).to eq(autor.id)

    # 4. lock_version incrementado (0 → 1)
    expect(recarregada.lock_version).to eq(1)

    # 5. evento publicado UMA única vez, com o payload do avanço
    expect(eventos.size).to eq(1)
    expect(eventos.first.payload).to include(task_id: tarefa.id, to_progress: 20, status: 'Em Andamento')
  end
end
