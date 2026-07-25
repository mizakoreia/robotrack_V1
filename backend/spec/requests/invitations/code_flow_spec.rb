# frozen_string_literal: true

require 'rails_helper'

# invite-by-code G2.7 — o fluxo por CÓDIGO espelhando o do token, reusando o mesmo
# `consume` (design D4). Cada condição da invariante 6 continua com seu código; o
# código adiciona só o par e-mail (anti-enumeração, D5), o estado do código
# (expirado/travado, D7) e a criação que devolve o claro UMA vez (D9).
RSpec.describe 'Fluxo de convite por código', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:joao)  { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }

  let(:owner_person) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  # Cria o convite pelo model e devolve [invitation, código_em_claro]. O claro só
  # existe no objeto recém-criado (attr transiente).
  def seed_invitation(email: 'joao@fabrica.com', role: 'view', **attrs)
    inv = in_workspace(ws) { Invitation.create!(email: email, role: role, created_by_person: owner_person, **attrs) }
    [inv, inv.short_code]
  end

  def accept_by_code(code, email, user, extra: {})
    post '/api/v1/invitations/code/accept',
         params: { code: code, email: email }.merge(extra), headers: auth_headers(user)
  end

  def preview_by_code(code, email)
    post '/api/v1/invitations/code/preview', params: { code: code, email: email }
  end

  def memberships_of(workspace)
    in_workspace(workspace) { Membership.all.to_a }
  end

  describe 'criação devolve o código UMA vez (D9)' do
    before { owner_person }

    it 'POST /invitations retorna short_code no formato XXXX-XXXX, sem code_hash' do
      post '/api/v1/invitations',
           params: { email: 'joao@fabrica.com', role: 'view' },
           headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['short_code']).to match(/\A[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}\z/)
      expect(body).not_to have_key('code_hash')
      expect(body['code_status']).to eq('active')
    end

    it 'a LISTAGEM de pendentes não reexpõe o claro, mas traz code_status' do
      post '/api/v1/invitations',
           params: { email: 'joao@fabrica.com', role: 'view' },
           headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)

      get '/api/v1/invitations', headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
      item = JSON.parse(response.body).first
      expect(item).not_to have_key('short_code')
      expect(item).not_to have_key('code_hash')
      expect(item['code_status']).to eq('active')
      expect(item['invite_url']).to match(%r{/convite/rt_inv_})
    end
  end

  describe 'aceite por código bem-sucedido' do
    it 'responde 200, cria UMA membership com o papel do convite e marca o convite' do
      _inv, code = seed_invitation(role: 'edit')

      accept_by_code(code, 'joao@fabrica.com', joao)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('workspace_id' => ws.id, 'role' => 'edit')

      memberships = memberships_of(ws)
      expect(memberships.size).to eq(1)
      expect(memberships.first).to have_attributes(role: 'edit', user_id: joao.id)
    end

    it 'aceita o código digitado em minúsculas e com hífen (normalização tolerante)' do
      _inv, code = seed_invitation(role: 'view')
      digitado = code.downcase # ex.: "4k7p9qmx" (sem hífen) ou já com traço

      accept_by_code(digitado, 'joao@fabrica.com', joao)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'defesas do par e do estado do código' do
    it 'e-mail SUBMETIDO diferente do convite: 404 genérico, não consome' do
      _inv, code = seed_invitation

      accept_by_code(code, 'errado@fabrica.com', joao)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('invitation_not_found')
      expect(memberships_of(ws)).to be_empty
    end

    it 'e-mail AUTENTICADO diferente do convite (par certo): 403 email_mismatch' do
      ana = create(:user, name: 'Ana Intrusa', email: 'ana-intrusa@fabrica.com')
      _inv, code = seed_invitation(email: 'joao@fabrica.com')

      # Ana conhece o código E o e-mail do convite (par casa), mas está autenticada
      # como outra conta — a condição 5 do consume barra.
      accept_by_code(code, 'joao@fabrica.com', ana)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('invitation_email_mismatch')
      expect(memberships_of(ws)).to be_empty
    end

    it 'código expirado: 410 invitation_code_expired, mas o LINK ainda consome' do
      inv, code = seed_invitation(role: 'view')
      in_workspace(ws) { Invitation.where(id: inv.id).update_all(code_expires_at: 1.hour.ago) }

      accept_by_code(code, 'joao@fabrica.com', joao)
      expect(response).to have_http_status(:gone)
      expect(JSON.parse(response.body)['error']).to eq('invitation_code_expired')
      expect(memberships_of(ws)).to be_empty

      # O link (7 dias) segue válido.
      post "/api/v1/invitations/#{inv.token}/accept", headers: auth_headers(joao)
      expect(response).to have_http_status(:ok)
      expect(memberships_of(ws).size).to eq(1)
    end

    it 'role no corpo do aceite por código: 422 unexpected_parameter, não consome' do
      _inv, code = seed_invitation(role: 'view')

      accept_by_code(code, 'joao@fabrica.com', joao, extra: { role: 'edit' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('unexpected_parameter')
      expect(memberships_of(ws)).to be_empty
    end

    it 'aceitar o mesmo código duas vezes: segundo recebe 409 already_used' do
      _inv, code = seed_invitation(role: 'view')

      accept_by_code(code, 'joao@fabrica.com', joao)
      expect(response).to have_http_status(:ok)

      accept_by_code(code, 'joao@fabrica.com', joao)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('invitation_already_used')
      expect(memberships_of(ws).size).to eq(1)
    end
  end

  describe 'preview por código exige o par (D5)' do
    it 'par correto revela a pré-visualização mascarada' do
      _inv, code = seed_invitation(role: 'view')

      preview_by_code(code, 'joao@fabrica.com')

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include('workspace_name' => 'Linha 3', 'role' => 'view',
                              'email_masked' => 'j***@fabrica.com', 'status' => 'pending')
      expect(body.keys).to contain_exactly('workspace_name', 'role', 'email_masked', 'expires_at', 'status')
    end

    it 'código certo com e-mail errado responde igual a código inexistente' do
      _inv, code = seed_invitation

      preview_by_code(code, 'errado@fabrica.com')
      corpo_par_errado = response.body
      status_par_errado = response.status

      preview_by_code('ZZZZZZZZ', 'errado@fabrica.com')
      expect(response.status).to eq(status_par_errado)
      expect(response.body).to eq(corpo_par_errado)
      expect(status_par_errado).to eq(404)
    end
  end

  describe 'o fluxo do token permanece intacto (regressão)' do
    it 'aceite por token de um convite que também tem código ainda funciona' do
      inv, _code = seed_invitation(role: 'edit')

      post "/api/v1/invitations/#{inv.token}/accept", headers: auth_headers(joao)
      expect(response).to have_http_status(:ok)
      expect(memberships_of(ws).size).to eq(1)
    end
  end
end
