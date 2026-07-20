# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'

# workspace-core §"Seleção do workspace corrente" + tenant-isolation §"Contexto"
# (tarefas 4.1, 4.2, 4.5). Exercita a fiação HTTP pela sonda de domínio.
RSpec.describe 'Contexto de tenant no HTTP', :tenancy, type: :request do
  let(:owner) { create(:user) }
  let(:ws) { make_workspace(owner: owner, name: 'WS-A') }

  def json
    JSON.parse(response.body)
  end

  def ctx(user, workspace_id: nil)
    h = auth_headers(user)
    h['X-Workspace-Id'] = workspace_id if workspace_id
    get '/api/v1/tenancy_probe/context', headers: h
  end

  it 'sem X-Workspace-Id devolve 400 workspace_context_missing' do
    ctx(owner)
    expect(response).to have_http_status(400)
    expect(json['error']).to eq('workspace_context_missing')
  end

  it 'workspace alheio devolve 403 workspace_access_denied (não 404)' do
    outra = make_workspace(name: 'WS-B')
    ctx(owner, workspace_id: outra.id)
    expect(response).to have_http_status(403)
    expect(json['error']).to eq('workspace_access_denied')
  end

  it 'workspace inexistente devolve 403, não 404 (não vaza existência)' do
    ctx(owner, workspace_id: SecureRandom.uuid)
    expect(response).to have_http_status(403)
    expect(json['error']).to eq('workspace_access_denied')
  end

  it 'dono abre o contexto e resolve role owner' do
    ctx(owner, workspace_id: ws.id)
    expect(response).to have_http_status(200)
    expect(json['workspace_id']).to eq(ws.id)
    expect(json['role']).to eq('owner')
    expect(json['db_workspace_id']).to eq(ws.id) # o SET LOCAL chegou ao banco
  end

  it 'membro edit resolve role edit no servidor' do
    member = create(:user)
    in_workspace(ws) do
      person = Person.create!(name: 'Membro Edit', email: member.email, user_id: member.id)
      Membership.create!(workspace_id: ws.id, user: member, person: person, role: 'edit')
    end
    ctx(member, workspace_id: ws.id)
    expect(response).to have_http_status(200)
    expect(json['role']).to eq('edit')
  end

  # 4.5 — vazamento entre requests.
  it 'exceção numa request não deixa contexto sujo para a próxima' do
    h = auth_headers(owner)
    h['X-Workspace-Id'] = ws.id
    get '/api/v1/tenancy_probe/boom', headers: h
    expect(response).to have_http_status(500)

    # Fora de qualquer request/contexto, a conexão vê a variável limpa.
    val = ActiveRecord::Base.connection.select_value("SELECT current_setting('app.current_workspace_id', true)")
    expect(val.to_s).to eq('')
  end
end
