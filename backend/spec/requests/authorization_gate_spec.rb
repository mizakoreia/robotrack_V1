# frozen_string_literal: true

require 'rails_helper'

# authorization-policies G2 (tarefas 2.2, 2.3, 2.4, 2.7) — o gate no Grape:
# decisão única por request, ANTES do service, fail-closed para rota não
# declarada, e contrato de negação sem vazamento de detalhe.
RSpec.describe 'Gate de autorização', :tenancy, type: :request do
  let(:owner)  { create(:user, name: 'Dona Ana') }
  let(:ws)     { make_workspace(owner: owner) }
  let(:viewer) { create(:user, name: 'Vera View') }
  let(:fora)   { create(:user, name: 'Diego De Fora') }

  def headers_for(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  describe 'a flag de rollout (2.2)' do
    it 'está LIGADA em test — desligar aqui vermelha este spec de propósito' do
      expect(ENV['AUTHZ_ENFORCE']).to eq('1')
      expect(Api::Root.authz_enforced?).to be(true)
    end
  end

  describe 'a negação acontece ANTES do service (inv. 1)' do
    before { add_member(ws, viewer, 'view') }

    it 'view em DELETE de membership: 403 e o service registra ZERO invocações' do
      alvo = in_workspace(ws) { Membership.find_by(user_id: viewer.id) }

      expect(Memberships::RemoveService).not_to receive(:new)
      delete "/api/v1/memberships/#{alvo.id}", headers: headers_for(viewer)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to eq('error' => 'forbidden')
    end
  end

  describe 'contrato de negação (2.4 / D3.12)' do
    before { add_member(ws, viewer, 'view') }

    it '403 tem exatamente a chave error e não revela papel, policy nem action' do
      post '/api/v1/invitations',
           params: { email: 'x@ex.com', role: 'edit' },
           headers: headers_for(viewer)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body).keys).to eq(['error'])
      expect(response.body).not_to include('owner', 'edit?', 'InvitationPolicy', 'manage_membership')
    end
  end

  describe 'rota sem declaração falha fechada (2.1 / 2.3 / D3.4)' do
    before { add_member(ws, viewer, 'view') }

    it 'em test, responde 500 undeclared_route citando o path — nunca 200' do
      allow_any_instance_of(Grape::Endpoint)
        .to receive(:route_setting).with(:policy).and_return(nil)

      get '/api/v1/memberships', headers: headers_for(viewer)

      expect(response).to have_http_status(:internal_server_error)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('undeclared_route')
      expect(body['message']).to match(/GET .*memberships/)
    end

    it 'em produção, responde 500 sem dado de domínio e reporta ao rastreio' do
      allow_any_instance_of(Grape::Endpoint)
        .to receive(:route_setting).with(:policy).and_return(nil)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(ErrorReporter).to receive(:report).at_least(:once)

      get '/api/v1/memberships', headers: headers_for(viewer)

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)).to eq('error' => 'internal_error')
      expect(response.body).not_to include(viewer.name)
    end
  end

  describe 'X-Skip-Auth não contorna nada (2.7 — regressão da brecha do template)' do
    it 'sem credencial, o header de bypass ainda responde 401' do
      get '/api/v1/memberships',
          headers: { 'X-Skip-Auth' => '1', 'X-Workspace-Id' => ws.id }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('role')
    end

    it 'com credencial de NÃO-membro, o header não abre o workspace alheio' do
      get '/api/v1/memberships',
          headers: headers_for(fora).merge('X-Skip-Auth' => '1')

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('workspace_access_denied')
      expect(response.body).not_to include(owner.name)
    end
  end
end
