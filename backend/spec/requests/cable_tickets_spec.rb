# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 1.1 / D6.8 — `POST /api/v1/cable_tickets`. Troca o Bearer
# JWT (no header, fora de qualquer log de URL) por um ticket opaco de 60s e uso
# único. Rota autenticada mas NÃO de domínio: não exige `X-Workspace-Id` — a
# autorização por membership é do `WorkspaceChannel`, depois. Sem Bearer, 401 pelo
# gate central de `Api::Root`.
RSpec.describe 'realtime-collaboration — POST /api/v1/cable_tickets', type: :request do
  let(:user) { create(:user, name: 'Ana Dona') }

  it 'emite um ticket de 60s para o usuário autenticado, sem exigir workspace' do
    post '/api/v1/cable_tickets', headers: auth_headers(user)

    expect(response).to have_http_status(:ok).or have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body['ticket']).to be_present
    expect(body['ttl']).to eq(60)

    # o ticket emitido resolve para o dono do Bearer (e some ao ser consumido).
    expect(Realtime::CableTicketService.consume(body['ticket'])).to eq(user)
  end

  it 'devolve tickets distintos a cada chamada (uso único, sem reaproveitar)' do
    post '/api/v1/cable_tickets', headers: auth_headers(user)
    first = JSON.parse(response.body)['ticket']
    post '/api/v1/cable_tickets', headers: auth_headers(user)
    second = JSON.parse(response.body)['ticket']

    expect(first).not_to eq(second)
  end

  it 'exige autenticação: sem Bearer, 401' do
    post '/api/v1/cable_tickets'

    expect(response).to have_http_status(:unauthorized)
  end
end
