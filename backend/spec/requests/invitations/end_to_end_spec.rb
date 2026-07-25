# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations 5.5 — o fluxo COMPLETO, ponta a ponta, no servidor.
#
# code-only-invites: o percurso é EXCLUSIVAMENTE por CÓDIGO (o link por token foi
# removido). Não há harness de E2E de navegador aqui (Playwright é escopo de
# `quality-and-accessibility`), então o fluxo é coberto por este teste, que
# percorre o ciclo inteiro pela API real, e o teste de cliente da rotina
# `handleAccessRevoked`. Registrado como desvio consciente no EXECUCAO.md.
#
# O percurso: o dono convida (recebe o CÓDIGO) → o convidado (sem sessão)
# pré-visualiza pelo par código+e-mail → autentica → aceita e vira membro → usa o
# workspace → o dono remove → a próxima requisição do convidado é
# `403 workspace_access_revoked` → e um "reload" NÃO o traz de volta.
RSpec.describe 'Ciclo completo do convite (por código)', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:joao)  { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }

  before do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  it 'convida, pré-visualiza sem sessão, aceita, usa e é expulso ao vivo' do
    # 1. O dono cria o convite e recebe o CÓDIGO curto (uma vez).
    post '/api/v1/invitations',
         params: { email: 'joao@fabrica.com', role: 'edit' },
         headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
    expect(response).to have_http_status(:created)
    codigo = JSON.parse(response.body)['short_code']
    expect(codigo).to match(/\A[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}\z/)

    # 2. O convidado pré-visualiza SEM sessão, pelo par código+e-mail, e vê para
    #    onde está sendo convidado — sem o e-mail completo e sem o id do workspace.
    post '/api/v1/invitations/code/preview', params: { code: codigo, email: 'joao@fabrica.com' }
    expect(response).to have_http_status(:ok)
    preview = JSON.parse(response.body)
    expect(preview).to include('workspace_name' => 'Linha 3', 'role' => 'edit',
                               'email_masked' => 'j***@fabrica.com', 'status' => 'pending')
    expect(response.body).not_to include('joao@fabrica.com')
    expect(response.body).not_to include(ws.id)

    # 3. Autentica e aceita pelo par (sem X-Workspace-Id).
    post '/api/v1/invitations/code/accept',
         params: { code: codigo, email: 'joao@fabrica.com' }, headers: auth_headers(joao)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include('workspace_id' => ws.id, 'role' => 'edit')

    # 4. É membro de verdade: o workspace aparece no índice dele e ele lê a equipe.
    get '/api/v1/workspaces', headers: auth_headers(joao)
    expect(JSON.parse(response.body).map { |w| w['id'] }).to include(ws.id)

    get '/api/v1/memberships', headers: auth_headers(joao).merge('X-Workspace-Id' => ws.id)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).map { |m| m['email'] }).to include('joao@fabrica.com')

    # 5. Mas continua sendo `edit`: convidar é do dono.
    post '/api/v1/invitations',
         params: { email: 'terceiro@fabrica.com', role: 'view' },
         headers: auth_headers(joao).merge('X-Workspace-Id' => ws.id)
    expect(response).to have_http_status(:forbidden)

    # 6. O dono remove o membro.
    membership = in_workspace(ws) { Membership.find_by(user_id: joao.id) }
    delete "/api/v1/memberships/#{membership.id}",
           headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
    expect(response).to have_http_status(:no_content)

    # 7. A PRÓXIMA requisição do convidado é negada com o código de revogação —
    #    o gatilho da rotina do cliente, sem depender de ActionCable.
    get '/api/v1/memberships', headers: auth_headers(joao).merge('X-Workspace-Id' => ws.id)
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)['error']).to eq('workspace_access_revoked')

    # 8. O "reload" não o traz de volta: o workspace sumiu do índice dele.
    get '/api/v1/workspaces', headers: auth_headers(joao)
    expect(JSON.parse(response.body).map { |w| w['id'] }).not_to include(ws.id)

    # 9. A Person sobrevive (o histórico dela não se parte) e o convite consumido
    #    continua lá como prova de por que aquele acesso existiu.
    pessoa = in_workspace(ws) { Person.find_by(email: 'joao@fabrica.com') }
    expect(pessoa).to be_present
    expect(pessoa.user_id).to be_nil

    convite = in_workspace(ws) { Invitation.find_by(email: 'joao@fabrica.com') }
    expect(convite.used_at).to be_present
    expect(convite.used_by_user_id).to eq(joao.id)

    # 10. E o mesmo código não readmite ninguém: o convite é de uso único.
    post '/api/v1/invitations/code/accept',
         params: { code: codigo, email: 'joao@fabrica.com' }, headers: auth_headers(joao)
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)['error']).to eq('invitation_already_used')
  end

  it 'readmitir exige convite NOVO, e ele funciona' do
    post '/api/v1/invitations', params: { email: 'joao@fabrica.com', role: 'view' },
                                headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
    primeiro = JSON.parse(response.body)['short_code']
    post '/api/v1/invitations/code/accept',
         params: { code: primeiro, email: 'joao@fabrica.com' }, headers: auth_headers(joao)
    membership = in_workspace(ws) { Membership.find_by(user_id: joao.id) }
    delete "/api/v1/memberships/#{membership.id}",
           headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)

    # O convite consumido não bloqueia o novo (o índice único é só de PENDENTES).
    post '/api/v1/invitations', params: { email: 'joao@fabrica.com', role: 'edit' },
                                headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
    expect(response).to have_http_status(:created)
    segundo = JSON.parse(response.body)['short_code']

    post '/api/v1/invitations/code/accept',
         params: { code: segundo, email: 'joao@fabrica.com' }, headers: auth_headers(joao)
    expect(response).to have_http_status(:ok)
    expect(in_workspace(ws) { Membership.find_by(user_id: joao.id) }.role).to eq('edit')

    # Uma única Person o tempo todo — a readmissão reencontra a mesma pessoa.
    expect(in_workspace(ws) { Person.where(email: 'joao@fabrica.com').count }).to eq(1)
  end
end
