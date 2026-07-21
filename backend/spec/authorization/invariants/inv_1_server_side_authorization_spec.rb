# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 1 — "a autorização é validada no servidor, sempre".
# Prova por HTTP: a decisão acontece no gate de Api::Root, antes de qualquer
# service; esconder botão na UI é conveniência, não segurança. O mecanismo que
# impede regressão é o route-sweep (spec/authorization/route_sweep_spec.rb).
RSpec.describe 'Invariante 1 — autorização no servidor, antes do service', :tenancy, type: :request do
  let(:ana)   { create(:user) }
  let(:ws)    { make_workspace(owner: ana) }
  let(:clara) { create(:user) }

  before { add_member(ws, clara, 'view') }

  it 'a requisição negada registra ZERO invocações do service' do
    expect(Invitations::CreateService).not_to receive(:new)

    post '/api/v1/invitations',
         params: { email: 'x@ex.com', role: 'edit' },
         headers: auth_headers(clara).merge('X-Workspace-Id' => ws.id)

    expect(response).to have_http_status(:forbidden)
  end

  it 'a mesma chamada direta à API, sem passar por tela nenhuma, é negada' do
    bruno = create(:user)
    add_member(ws, bruno, 'edit')
    alvo = in_workspace(ws) { Membership.find_by(user_id: bruno.id) }

    patch "/api/v1/memberships/#{alvo.id}",
          params: { role: 'view' },
          headers: auth_headers(clara).merge('X-Workspace-Id' => ws.id)

    expect(response).to have_http_status(:forbidden)
    expect(in_workspace(ws) { Membership.find_by(user_id: bruno.id).role }).to eq('edit')
  end
end
