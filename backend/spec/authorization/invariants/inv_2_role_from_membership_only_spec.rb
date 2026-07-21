# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 2 — o papel vem exclusivamente da associação resolvida no
# servidor (dono pela coluna `owner_user_id`, senão `memberships.role`).
# Claim de JWT e qualquer dado enviado pelo cliente não concedem NADA.
RSpec.describe 'Invariante 2 — papel só da membership', :tenancy, type: :request do
  let(:ana)   { create(:user) }
  let(:ws)    { make_workspace(owner: ana) }
  let(:diego) { create(:user) }

  it 'JWT válido com claim role:"owner" adulterado não concede acesso' do
    now = Time.now.to_i
    payload = {
      'sub' => diego.id.to_s, 'jti' => SecureRandom.uuid,
      'iat' => now, 'iat_origin' => now, 'exp' => now + 3600,
      'role' => 'owner', 'workspace_id' => ws.id
    }
    token = JWT.encode(payload, Auth::TokenService.secret, Auth::TokenService::ALGORITHM)

    get '/api/v1/memberships',
        headers: { 'Authorization' => "Bearer #{token}", 'X-Workspace-Id' => ws.id }

    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)['error']).to eq('workspace_access_denied')
    expect(response.body).not_to include(ana.email)
  end

  it 'membership removida derruba o acesso no request seguinte, com o MESMO token' do
    bruno = create(:user)
    add_member(ws, bruno, 'edit')
    headers = auth_headers(bruno).merge('X-Workspace-Id' => ws.id)

    get '/api/v1/memberships', headers: headers
    expect(response).to have_http_status(:ok)

    in_workspace(ws) { Membership.find_by(user_id: bruno.id).destroy! }

    get '/api/v1/memberships', headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(ana.email)
  end

  it 'papel fora do enum é rejeitado pelo banco antes de qualquer model' do
    bruno = create(:user)
    add_member(ws, bruno, 'edit')

    expect do
      in_workspace(ws) do
        ActiveRecord::Base.connection.execute(
          "UPDATE memberships SET role = 'admin' WHERE user_id = #{ActiveRecord::Base.connection.quote(bruno.id)}"
        )
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum membership_role/)
  end
end
