# frozen_string_literal: true

require 'rails_helper'

# team-access-management, verificação do grupo 4 (tarefas 4.1–4.4, 4.7).
#
# O critério mais fino está no último bloco: recurso de OUTRO workspace responde
# `404`, não `403`. Os dois status parecem intercambiáveis e não são — `403`
# afirmaria "isto existe, mas não é seu", e essa afirmação é o vazamento. A RLS
# esconde a linha e o serviço não tem o que negar: ele não a encontra.
RSpec.describe 'Painel de equipe', :tenancy, type: :request do
  let(:owner)  { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)     { make_workspace(owner: owner, name: 'Linha 3') }
  let(:editor) { create(:user, name: 'Edu Edit', email: 'edu@fabrica.com') }
  let(:viewer) { create(:user, name: 'Vera View', email: 'vera@fabrica.com') }

  let!(:owner_person) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  def headers_for(user, workspace)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def membership_of(user, workspace = ws)
    in_workspace(workspace) { Membership.find_by(user_id: user.id) }
  end

  describe 'listagem (4.4)' do
    before do
      add_member(ws, editor, 'edit')
      add_member(ws, viewer, 'view')
    end

    it 'inclui o dono (que não tem linha de membership) e os dois membros' do
      get '/api/v1/memberships', headers: headers_for(owner, ws)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(3)

      dono = body.find { |m| m['is_owner'] }
      expect(dono).to include('role' => 'owner', 'email' => 'ana@fabrica.com')
      expect(body.map { |m| m['role'] }).to contain_exactly('owner', 'edit', 'view')
    end

    it 'membro edit LÊ a lista (a UI é conveniência; a autorização é do servidor)' do
      get '/api/v1/memberships', headers: headers_for(editor, ws)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'mudança de papel (4.1)' do
    before { add_member(ws, viewer, 'view') }

    it 'o dono promove view → edit' do
      alvo = membership_of(viewer)

      patch "/api/v1/memberships/#{alvo.id}", params: { role: 'edit' }, headers: headers_for(owner, ws)

      expect(response).to have_http_status(:ok)
      expect(membership_of(viewer).role).to eq('edit')
    end

    it 'role "owner" é 422 invalid_role e o papel não muda' do
      alvo = membership_of(viewer)

      patch "/api/v1/memberships/#{alvo.id}", params: { role: 'owner' }, headers: headers_for(owner, ws)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('invalid_role')
      expect(membership_of(viewer).role).to eq('view')
    end

    it 'o dono rebaixando a si mesmo é 422 owner_is_immutable' do
      patch "/api/v1/memberships/#{owner_person.id}", params: { role: 'edit' },
                                                      headers: headers_for(owner, ws)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('owner_is_immutable')
      expect(in_workspace(ws) { Workspace.find(ws.id) }.owner_user_id).to eq(owner.id)
    end

    it 'membro view mudando papel de outro é 403 (4.7)' do
      add_member(ws, editor, 'edit')
      alvo = membership_of(editor)

      patch "/api/v1/memberships/#{alvo.id}", params: { role: 'view' }, headers: headers_for(viewer, ws)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('forbidden')
      expect(membership_of(editor).role).to eq('edit')
    end
  end

  describe 'remoção de membro (4.2, 4.3)' do
    let!(:convite) do
      in_workspace(ws) do
        Invitation.create!(email: 'edu@fabrica.com', role: 'edit', created_by_person: owner_person)
      end
    end

    before do
      post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(editor)
      expect(response).to have_http_status(:ok)
    end

    it 'remove a membership, PRESERVA a Person e limpa o user_id dela' do
      alvo = membership_of(editor)
      pessoa_id = alvo.person_id

      delete "/api/v1/memberships/#{alvo.id}", headers: headers_for(owner, ws)

      expect(response).to have_http_status(:no_content)
      expect(membership_of(editor)).to be_nil

      pessoa = in_workspace(ws) { Person.find(pessoa_id) }
      expect(pessoa).to be_present
      expect(pessoa.user_id).to be_nil
      expect(pessoa.email).to eq('edu@fabrica.com')
    end

    it 'preserva o convite consumido (a prova auditável do acesso)' do
      delete "/api/v1/memberships/#{membership_of(editor).id}", headers: headers_for(owner, ws)

      recarregado = in_workspace(ws) { Invitation.find(convite.id) }
      expect(recarregado.used_at).to be_present
      expect(recarregado.used_by_user_id).to eq(editor.id)
    end

    it 'grava o snapshot append-only ANTES de remover (4.2)' do
      alvo = membership_of(editor)

      delete "/api/v1/memberships/#{alvo.id}", headers: headers_for(owner, ws)

      snapshot = in_workspace(ws) { MembershipRevocation.last }
      expect(snapshot).to have_attributes(
        workspace_id: ws.id, user_id: editor.id, person_id: alvo.person_id,
        role: 'edit', invitation_id: convite.id, removed_by_user_id: owner.id
      )
    end

    it 'o snapshot NÃO é editável nem apagável pelo runtime' do
      delete "/api/v1/memberships/#{membership_of(editor).id}", headers: headers_for(owner, ws)

      in_workspace(ws) do
        snapshot = MembershipRevocation.last
        conn = ActiveRecord::Base.connection
        expect do
          conn.execute("DELETE FROM membership_revocations WHERE id = #{conn.quote(snapshot.id)}")
        end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      end
    end

    it 'publica o evento membership_revoked (5.4)' do
      alvo = membership_of(editor)
      capturado = nil
      ActiveSupport::Notifications.subscribe('membership.revoked') { |*, payload| capturado = payload }

      delete "/api/v1/memberships/#{alvo.id}", headers: headers_for(owner, ws)

      expect(capturado).to include(
        type: 'membership_revoked', workspace_id: ws.id, user_id: editor.id
      )
    ensure
      ActiveSupport::Notifications.unsubscribe('membership.revoked')
    end

    it 'o dono não pode remover a si mesmo (422 cannot_remove_owner)' do
      delete "/api/v1/memberships/#{owner_person.id}", headers: headers_for(owner, ws)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('cannot_remove_owner')
    end

    it 'membro edit revogando convite é 403 e o convite permanece (4.7)' do
      outro_convite = in_workspace(ws) do
        Invitation.create!(email: 'novo@fabrica.com', role: 'view', created_by_person: owner_person)
      end

      delete "/api/v1/invitations/#{outro_convite.id}", headers: headers_for(editor, ws)

      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { Invitation.find_by(id: outro_convite.id) }).to be_present
    end
  end

  describe 'revogação detectada pelo cliente (5.3 / D-INV-7)' do
    before do
      add_member(ws, editor, 'edit')
      delete "/api/v1/memberships/#{membership_of(editor).id}", headers: headers_for(owner, ws)
      expect(response).to have_http_status(:no_content)
    end

    it 'a próxima requisição do removido responde 403 workspace_access_revoked' do
      get '/api/v1/memberships', headers: headers_for(editor, ws)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('workspace_access_revoked')
    end

    it 'quem NUNCA teve acesso continua recebendo o mesmo workspace_access_denied' do
      estranho = create(:user, email: 'estranho@fabrica.com')

      get '/api/v1/memberships', headers: headers_for(estranho, ws)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('workspace_access_denied')
    end

    it 'workspace INEXISTENTE responde igual a workspace alheio (anti-enumeração)' do
      estranho = create(:user, email: 'estranho2@fabrica.com')
      inexistente = SecureRandom.uuid

      get '/api/v1/memberships', headers: auth_headers(estranho).merge('X-Workspace-Id' => inexistente)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('workspace_access_denied')
    end

    it 'a sessão do removido NÃO é invalidada: ele segue no próprio workspace' do
      proprio = make_workspace(owner: editor, name: 'Workspace de Edu')

      get '/api/v1/workspaces', headers: auth_headers(editor)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |w| w['id'] }).to include(proprio.id)
    end
  end

  describe 'membership de OUTRO workspace é 404, não 403 (4.7)' do
    it 'mudança de papel sobre membership de WS-B' do
      dono_b = create(:user, email: 'dono.b@fabrica.com')
      ws_b = make_workspace(owner: dono_b, name: 'Linha 9')
      membro_b = create(:user, email: 'membro.b@fabrica.com')
      add_member(ws_b, membro_b, 'view')
      alvo = in_workspace(ws_b, user: dono_b) { Membership.find_by(user_id: membro_b.id) }

      patch "/api/v1/memberships/#{alvo.id}", params: { role: 'edit' }, headers: headers_for(owner, ws)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('membership_not_found')
      expect(in_workspace(ws_b, user: dono_b) { Membership.find(alvo.id) }.role).to eq('view')
    end
  end
end
