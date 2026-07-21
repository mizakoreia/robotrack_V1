# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 6 — o consumo do convite é atômico e de uso único.
#
# O mecanismo (transação com `SELECT … FOR UPDATE`, índice único parcial em
# memberships.invitation_id, CHECK de coerência used_at/used_by) e a prova de
# CONCORRÊNCIA real (duas threads, um token, uma membership) são de
# `workspace-invitations` — ver spec/invitations/. Aqui fica a prova de
# AUTORIZAÇÃO por HTTP: o segundo consumo do mesmo token é negado.
RSpec.describe 'Invariante 6 — convite de uso único', :tenancy, type: :request do
  let(:ana) { create(:user) }
  let(:ws)  { make_workspace(owner: ana) }

  it 'aceitar o mesmo token duas vezes: a segunda responde 409 e nada muda' do
    convidada = create(:user, email: "convidada#{SecureRandom.hex(4)}@ex.com")
    token = "rt_inv_#{SecureRandom.urlsafe_base64(32)}"

    in_workspace(ws) do
      pessoa_ana = Person.create!(name: ana.name, email: ana.email, user_id: ana.id)
      Invitation.create!(workspace_id: ws.id, email: convidada.email, role: 'edit',
                         token: token, created_by_person_id: pessoa_ana.id)
    end

    post "/api/v1/invitations/#{token}/accept", headers: auth_headers(convidada)
    expect(response).to have_http_status(:ok)

    post "/api/v1/invitations/#{token}/accept", headers: auth_headers(convidada)
    expect(response).to have_http_status(:conflict)

    memberships = in_workspace(ws) { Membership.where(user_id: convidada.id).count }
    expect(memberships).to eq(1)
  end
end
