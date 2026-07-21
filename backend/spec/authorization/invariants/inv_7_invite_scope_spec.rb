# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 7 — convite só pelo dono, só para o PRÓPRIO workspace, só com
# papel `view`/`edit` (`firestore.rules` L72-77). Três camadas: policy
# (InvitationPolicy = manage_membership), service (workspace do contexto) e
# banco (enum invitation_role sem 'owner').
RSpec.describe 'Invariante 7 — escopo do convite', :tenancy, type: :request do
  let(:ana)   { create(:user) }
  let(:diego) { create(:user) }
  let(:ws_a)  { make_workspace(owner: ana) }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers_ana = auth_headers(ana).merge('X-Workspace-Id' => ws_a.id)

  it 'convite com papel owner é rejeitado (422) e o enum nem o representa' do
    post '/api/v1/invitations',
         params: { email: 'x@ex.com', role: 'owner' },
         headers: headers_ana

    expect(response).to have_http_status(:unprocessable_entity)

    conn = ActiveRecord::Base.connection
    expect do
      in_workspace(ws_a) do
        pessoa = Person.create!(name: ana.name, email: ana.email, user_id: ana.id)
        conn.execute(
          'INSERT INTO invitations (workspace_id, email, role, token, created_by_person_id) ' \
          "VALUES (#{conn.quote(ws_a.id)}, 'y@ex.com', 'owner', 'rt_inv_x', #{conn.quote(pessoa.id)})"
        )
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum invitation_role/)
  end

  it 'workspace_id do corpo apontando para OUTRO workspace é negado sem vazar nada' do
    post '/api/v1/invitations',
         params: { email: 'x@ex.com', role: 'edit', workspace_id: ws_b.id },
         headers: headers_ana

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)).to eq('error' => 'forbidden')
    expect(in_workspace(ws_b) { Invitation.count }).to eq(0)
  end

  it 'edit e view não criam nem revogam convite' do
    bruno = create(:user)
    add_member(ws_a, bruno, 'edit')

    post '/api/v1/invitations',
         params: { email: 'x@ex.com', role: 'view' },
         headers: auth_headers(bruno).merge('X-Workspace-Id' => ws_a.id)

    expect(response).to have_http_status(:forbidden)
  end
end
