# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 5 — o dono do workspace é imutável e único, por TRÊS camadas
# de banco (trigger `workspaces_owner_immutable`, REVOKE de coluna, trigger
# `memberships_owner_is_not_member`) e sem nenhuma action de transferência na
# matriz (D3.8, divergência D-B: dono não é mais inferido de uid == wsId).
RSpec.describe 'Invariante 5 — dono imutável e único', :tenancy, type: :request do
  let(:ana)   { create(:user) }
  let(:bruno) { create(:user) }
  let(:ws)    { make_workspace(owner: ana) }

  it 'a API ignora/rejeita tentativa do próprio dono de transferir a posse' do
    patch "/api/v1/workspaces/#{ws.id}",
          params: { owner_user_id: bruno.id },
          headers: auth_headers(ana)

    expect(response).to have_http_status(:unprocessable_entity)
    dono = in_workspace(ws) { Workspace.find(ws.id).owner_user_id }
    expect(dono).to eq(ana.id)
  end

  it 'a matriz não tem action de transferência' do
    expect(PermissionMatrix::ACTIONS.keys).not_to include(:transfer_ownership)
    expect(WorkspacePolicy).not_to respond_to(:transfer_ownership?)
  end

  it 'UPDATE direto no banco é bloqueado (REVOKE de coluna para o runtime)' do
    conn = ActiveRecord::Base.connection
    expect do
      in_workspace(ws) do
        conn.execute("UPDATE workspaces SET owner_user_id = #{conn.quote(bruno.id)} WHERE id = #{conn.quote(ws.id)}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /permission denied|owner_user_id/)

    # A camada de trigger (que segura até papel privilegiado) é provada em
    # spec/tenancy/schema_constraints_spec.rb, com conexão de robotrack_migrator.
  end
end
