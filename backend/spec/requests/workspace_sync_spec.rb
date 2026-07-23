# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 4.2 — `GET /api/v1/workspaces/:id/sync?since=`. Queda
# curta reconcilia por tipo; queda longa (nada mudou na janela de 10 min) cai para
# invalidação total; `since == current_seq` não devolve nada (senão todo reconnect
# viraria refetch completo); e não-membro recebe 403 sem vazar `current_seq`.
RSpec.describe 'realtime-collaboration — GET /api/v1/workspaces/:id/sync', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws) { make_workspace(owner: owner) }

  def sync(workspace_id, since:, as: owner)
    get "/api/v1/workspaces/#{workspace_id}/sync?since=#{since}", headers: auth_headers(as)
    JSON.parse(response.body)
  end

  it 'queda curta: enumera os tipos tocados na janela, gap=false' do
    # duas mutações recentes bumpam o realtime_seq e deixam linhas dentro da janela
    in_workspace(ws) do
      Project.create!(name: 'Linha A')
      Project.create!(name: 'Linha B')
    end

    body = sync(ws.id, since: 0)

    expect(response).to have_http_status(:ok)
    expect(body['current_seq']).to eq(2)
    expect(body['gap']).to be(false)
    expect(body['entity_kinds']).to include('project')
  end

  it 'queda longa: nada mudou na janela ⇒ gap=true, sem enumerar' do
    # eventos perdidos existem (seq avançou), mas não há linha recente: o que se
    # perdeu é antigo — o cliente invalida ['ws', w] inteiro.
    in_workspace(ws) { Workspace.where(id: ws.id).update_all(realtime_seq: 7) }

    body = sync(ws.id, since: 0)

    expect(response).to have_http_status(:ok)
    expect(body['current_seq']).to eq(7)
    expect(body['gap']).to be(true)
    expect(body['entity_kinds']).to eq([])
  end

  it 'since == current_seq: nada a invalidar' do
    in_workspace(ws) { Workspace.where(id: ws.id).update_all(realtime_seq: 5) }

    body = sync(ws.id, since: 5)

    expect(response).to have_http_status(:ok)
    expect(body['current_seq']).to eq(5)
    expect(body['gap']).to be(false)
    expect(body['entity_kinds']).to eq([])
  end

  it 'não-membro recebe 403 e a resposta não vaza current_seq nem tipos de W1' do
    intruso = create(:user, name: 'Ivo Intruso')
    in_workspace(ws) { Workspace.where(id: ws.id).update_all(realtime_seq: 9) }

    body = sync(ws.id, since: 0, as: intruso)

    expect(response).to have_http_status(:forbidden)
    expect(body).not_to have_key('current_seq')
    expect(body).not_to have_key('entity_kinds')
  end
end
