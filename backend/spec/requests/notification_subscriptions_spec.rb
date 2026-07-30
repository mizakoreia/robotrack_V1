# frozen_string_literal: true

require 'rails_helper'

# notification-preferences D-P6 — a API pessoal de preferência: escopo por pessoa,
# upsert idempotente, `default` apaga, e a impossibilidade estrutural de editar a
# preferência alheia (o endpoint não aceita `person_id`).
RSpec.describe 'notification-preferences — /api/v1/notification_subscriptions', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def person_id_of(user)
    in_workspace(ws) { ::Person.find_by(user_id: user.id)&.id }
  end

  def headers(user) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  def robot_in(workspace)
    in_workspace(workspace) do
      project = Project.create!(name: 'L', position: 0)
      cell = Cell.create!(project_id: project.id, name: 'C', position: 0)
      Robot.create!(cell_id: cell.id, name: 'R03', application: 'Handling', position: 0)
    end
  end

  describe 'PUT — upsert e default' do
    it 'seguir um robô cria a linha (idempotente) para a própria pessoa' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'edit')
      robot = robot_in(ws)

      2.times do
        put '/api/v1/notification_subscriptions',
            params: { scope_type: 'robot', scope_id: robot.id, state: 'follow' }, headers: headers(ana)
        expect(response).to have_http_status(:ok)
      end

      in_workspace(ws) do
        rows = NotificationSubscription.where(scope_robot_id: robot.id)
        expect(rows.count).to eq(1)
        expect(rows.first.person_id).to eq(person_id_of(ana))
        expect(rows.first.state).to eq('follow')
      end
    end

    it 'state default apaga a linha' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'edit')
      robot = robot_in(ws)
      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'mute' }, headers: headers(ana)

      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'default' }, headers: headers(ana)
      expect(response).to have_http_status(:ok)
      in_workspace(ws) { expect(NotificationSubscription.where(scope_robot_id: robot.id).count).to eq(0) }
    end

    it 'membro view gere a própria preferência (config pessoal, D-P6)' do
      leitor = create(:user, name: 'Léo'); add_member(ws, leitor, 'view')
      robot = robot_in(ws)
      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'mute' }, headers: headers(leitor)
      expect(response).to have_http_status(:ok)
      in_workspace(ws) do
        expect(NotificationSubscription.find_by(scope_robot_id: robot.id).person_id).to eq(person_id_of(leitor))
      end
    end
  end

  describe 'GET — só as próprias' do
    it 'Ana não vê as preferências de Bruno' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'edit')
      bruno = create(:user, name: 'Bruno'); add_member(ws, bruno, 'edit')
      robot = robot_in(ws)
      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'follow' }, headers: headers(ana)
      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'mute' }, headers: headers(bruno)

      get '/api/v1/notification_subscriptions', headers: headers(ana)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first['state']).to eq('follow')
      expect(body.first['scope_type']).to eq('robot')
    end
  end

  describe 'não edita a preferência alheia (D-P6)' do
    it 'o endpoint não aceita person_id: a linha criada é sempre da pessoa corrente' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'edit')
      bruno = create(:user, name: 'Bruno'); add_member(ws, bruno, 'edit')
      robot = robot_in(ws)
      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'mute', person_id: person_id_of(bruno) },
          headers: headers(ana)
      expect(response).to have_http_status(:ok)
      in_workspace(ws) do
        expect(NotificationSubscription.find_by(scope_robot_id: robot.id).person_id).to eq(person_id_of(ana))
      end
    end
  end

  describe 'isolamento cross-tenant (inv. 1)' do
    it 'não-membro do workspace é barrado' do
      estranho = create(:user, name: 'Estranho')
      robot = robot_in(ws)
      put '/api/v1/notification_subscriptions',
          params: { scope_type: 'robot', scope_id: robot.id, state: 'mute' }, headers: headers(estranho)
      expect(response.status).to be_in([403, 404])
    end
  end
end
