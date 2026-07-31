# frozen_string_literal: true

require 'rails_helper'

# Prova de que a notificação é criada INLINE (perform_now no subscriber), pela
# porta HTTP real, sem depender do Sidekiq — o conserto para o worker frágil do
# free tier. Espelha o cenário de produção: um colaborador `edit` avança uma
# tarefa e o DONO (que tem Person) recebe a notificação.
RSpec.describe 'Entrega inline de notificação (sem Sidekiq)', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }

  def headers(user)
    auth_headers(user).merge('X-Workspace-Id' => ws.id)
  end

  before { add_member(ws, bruno, 'edit') } # bruno ganha Person (autor)

  it 'avanço de colaborador cria notificação para o dono, pela porta HTTP' do
    owner_person, tarefa = in_workspace(ws) do
      op = Person.find_or_create_by!(user_id: ana.id) { |p| p.name = 'Ana' }
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      robo = Robot.create!(cell_id: celula.id, name: 'R-01')
      [op, create_task(robo, desc: 'Power On', progress: 0, status: 'Pendente', position: 0)]
    end

    post "/api/v1/tasks/#{tarefa.id}/advances",
         params: { id: SecureRandom.uuid, progress: 50, comment: 'teste inline', lock_version: 0 },
         headers: headers(bruno)
    expect(response).to have_http_status(:created)

    notis = in_workspace(ws) { Notification.where(recipient_person_id: owner_person.id).to_a }
    expect(notis.size).to eq(1)
    expect(notis.first.type).to eq('progress')
    expect(notis.first.msg).to include('Power On')
  end
end
