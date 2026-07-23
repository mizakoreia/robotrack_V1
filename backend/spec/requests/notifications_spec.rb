# frozen_string_literal: true

require 'rails_helper'

# in-app-notifications 5.1-5.4 — a API do centro de notificações: escopo por
# destinatário, marcar como lida (a PRÓPRIA), e as quatro negações de §4.1 inv. 4/1.
RSpec.describe 'in-app-notifications — /api/v1/notifications', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def person_id_of(user)
    in_workspace(ws) { ::Person.find_by(user_id: user.id)&.id }
  end

  def seed_notification(recipient:, actor:, msg: 'oi', ws_scope: ws, read: false)
    conn = ActiveRecord::Base.connection
    id = SecureRandom.uuid
    in_workspace(ws_scope) do
      conn.execute(<<~SQL)
        INSERT INTO notifications
          (id, workspace_id, recipient_person_id, actor_person_id, type, msg,
           author_name_snapshot, recorded_at, ts_local, read, format_version)
        VALUES
          (#{conn.quote(id)}, #{conn.quote(ws_scope.id)}, #{conn.quote(recipient)}, #{conn.quote(actor)},
           'assign', #{conn.quote(msg)}, 'Bruno', now(), '23/07 14:03', #{read}, 1)
      SQL
    end
    id
  end

  def headers(user) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  describe 'GET (5.1) — escopo por destinatário' do
    it 'Ana não vê as notificações de Bruno; header de não-lidas conta as dela' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'view')
      bruno = create(:user, name: 'Bruno'); add_member(ws, bruno, 'edit')
      ana_pid = person_id_of(ana); bruno_pid = person_id_of(bruno)

      seed_notification(recipient: ana_pid, actor: bruno_pid)
      seed_notification(recipient: ana_pid, actor: bruno_pid)
      seed_notification(recipient: bruno_pid, actor: ana_pid) # de Bruno — Ana não vê

      get '/api/v1/notifications', headers: headers(ana)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Unread-Count']).to eq('2')
    end
  end

  describe 'POST :id/read (5.2/5.3)' do
    it 'a destinatária marca a PRÓPRIA como lida (200)' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'view')
      bruno = create(:user, name: 'Bruno'); add_member(ws, bruno, 'edit')
      id = seed_notification(recipient: person_id_of(ana), actor: person_id_of(bruno))

      post "/api/v1/notifications/#{id}/read", headers: headers(ana)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['read']).to be(true)
    end

    it 'read_all marca todas as da pessoa' do
      ana = create(:user, name: 'Ana'); add_member(ws, ana, 'view')
      bruno = create(:user, name: 'Bruno'); add_member(ws, bruno, 'edit')
      2.times { seed_notification(recipient: person_id_of(ana), actor: person_id_of(bruno)) }

      post '/api/v1/notifications/read_all', headers: headers(ana)
      expect(response).to have_http_status(:ok)
      get '/api/v1/notifications', headers: headers(ana)
      expect(response.headers['X-Unread-Count']).to eq('0')
    end
  end

  describe 'negações (5.4 / §4.1 inv. 4 e 1)' do
    it 'um membro marcando a notificação de OUTRA pessoa como lida → 403 (a "própria")' do
      carla = create(:user, name: 'Carla'); add_member(ws, carla, 'view')
      bruno = create(:user, name: 'Bruno'); add_member(ws, bruno, 'edit')
      id = seed_notification(recipient: person_id_of(bruno), actor: person_id_of(carla))

      # Carla (membro) tenta marcar a notificação DE Bruno → negado (não é a dela).
      post "/api/v1/notifications/#{id}/read", headers: headers(carla)
      expect(response).to have_http_status(:forbidden)
    end

    it 'a superfície de escrita é MÍNIMA: sem PATCH/PUT genérico e sem POST de criação (route-sweep 5.2)' do
      paths = Api::V1::Notifications.routes.map { |r| "#{r.request_method} #{r.path}" }
      # nenhuma rota de update genérica (PATCH/PUT sobre a notificação)
      expect(paths.grep(/PATCH|PUT/)).to be_empty
      # nenhum POST na coleção (criação) — só read_all e :id/read
      expect(paths).not_to include(a_string_matching(%r{\APOST /notifications\(}))
      # a superfície é exatamente estas três
      methods = paths.map { |p| p.split.first }.uniq.sort
      expect(methods).to eq(%w[GET POST])
    end

    it 'membro do workspace A tocando notificação do B → 404 sem vazar a existência' do
      other_owner = create(:user, name: 'Outro')
      other_ws = make_workspace(owner: other_owner)
      other_person = in_workspace(other_ws) { ::Person.create!(name: 'X').id }
      id = seed_notification(recipient: other_person, actor: other_person, ws_scope: other_ws)

      # owner está no workspace `ws` (A); tenta tocar a notificação de B.
      post "/api/v1/notifications/#{id}/read", headers: headers(owner)
      expect(response).to have_http_status(:not_found)
    end
  end
end
