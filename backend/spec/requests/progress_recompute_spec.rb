# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 4.5 (§4.1 inv. 4) — o recálculo manual do workspace: owner/edit
# recomputam; `view` recebe 403 e nenhum UPDATE em progress_cache é emitido.
RSpec.describe 'Recálculo manual do progresso', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:clara) { create(:user, name: 'Clara View') }

  def headers(user) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  before { add_member(ws, clara, 'view') }

  it 'owner recomputa (200)' do
    in_workspace(ws) do
      proj = Project.create!(name: 'P')
      cel = Cell.create!(project_id: proj.id, name: 'C')
      robo = Robot.create!(cell_id: cel.id, name: 'R')
      create_task(robo, desc: 'T', weight: 1, progress: 100, status: 'Concluído', position: 0)
    end
    post '/api/v1/progress/recompute', headers: headers(ana)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['recomputed']).to be(true)
  end

  it 'view recebe 403 e nenhum UPDATE é emitido' do
    updates = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
      updates += 1 if p[:sql] =~ /UPDATE\s+(robots|cells|projects)/i
    end
    post '/api/v1/progress/recompute', headers: headers(clara)
    ActiveSupport::Notifications.unsubscribe(sub)

    expect(response).to have_http_status(:forbidden)
    expect(updates).to eq(0)
  end
end
