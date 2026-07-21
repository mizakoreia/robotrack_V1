# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations, verificação do grupo 2 (tarefa 2.5).
#
# O caminho feliz e os CINCO negativos da invariante 7. Em todos os negativos a
# asserção que importa não é só o status: é que a CONTAGEM de convites não muda.
# Um 403 que ainda assim insere a linha seria pior que um 200 honesto.
RSpec.describe 'Criação de convite', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }

  let(:editor) { create(:user, name: 'Edu Edit', email: 'edu@fabrica.com') }
  let(:viewer) { create(:user, name: 'Vera View', email: 'vera@fabrica.com') }

  def headers_for(user, workspace)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def invitation_count(workspace)
    in_workspace(workspace) { Invitation.count }
  end

  def post_invitation(user, workspace, params)
    post '/api/v1/invitations', params: params, headers: headers_for(user, workspace)
  end

  before do
    # A Person do dono existe (bootstrap da Onda 1 faz isso em produção).
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  describe 'caminho feliz' do
    it 'cria o convite normalizado e devolve o link absoluto' do
      post_invitation(owner, ws, { email: '  Joao@Fabrica.COM ', role: 'edit' })

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['email']).to eq('joao@fabrica.com')
      expect(body['role']).to eq('edit')
      expect(body['status']).to eq('pending')
      expect(body['invite_url']).to match(%r{\Ahttp://localhost:5173/convite/rt_inv_[A-Za-z0-9_-]{43}\z})
      # O token NUNCA sai como campo solto — só embutido no link.
      expect(body).not_to have_key('token')
      expect(body).not_to have_key('workspace_id')
    end

    it 'expira em 7 dias' do
      post_invitation(owner, ws, { email: 'joao@fabrica.com', role: 'view' })

      expires_at = Time.zone.parse(JSON.parse(response.body)['expires_at'])
      expect(expires_at).to be_within(1.minute).of(7.days.from_now)
    end

    it 'lista os pendentes do workspace corrente, com o link para recopiar' do
      post_invitation(owner, ws, { email: 'joao@fabrica.com', role: 'view' })
      post_invitation(owner, ws, { email: 'ana2@fabrica.com', role: 'edit' })

      get '/api/v1/invitations', headers: headers_for(owner, ws)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(2)
      expect(body.map { |i| i['email'] }).to contain_exactly('joao@fabrica.com', 'ana2@fabrica.com')
      expect(body).to all(include('invite_url' => a_string_matching(%r{/convite/rt_inv_})))
    end

    it 'recusa o segundo convite pendente para o mesmo e-mail (409)' do
      post_invitation(owner, ws, { email: 'joao@fabrica.com', role: 'view' })
      expect(response).to have_http_status(:created)

      expect { post_invitation(owner, ws, { email: 'joao@fabrica.com', role: 'edit' }) }
        .not_to(change { invitation_count(ws) })
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('invitation_already_pending')
    end
  end

  describe 'os cinco caminhos negativos (2.5)' do
    before do
      add_member(ws, editor, 'edit')
      add_member(ws, viewer, 'view')
    end

    it '(1) membro edit convidando: 403 e nenhuma linha criada' do
      expect { post_invitation(editor, ws, { email: 'x@fabrica.com', role: 'view' }) }
        .not_to(change { invitation_count(ws) })

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('forbidden')
    end

    it '(2) membro view convidando: 403 e nenhuma linha criada' do
      expect { post_invitation(viewer, ws, { email: 'x@fabrica.com', role: 'view' }) }
        .not_to(change { invitation_count(ws) })

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('forbidden')
    end

    it '(3) workspace_id de OUTRO workspace no corpo: 403 e nenhuma linha criada' do
      outro_dono = create(:user, email: 'dono.b@fabrica.com')
      ws_b = make_workspace(owner: outro_dono, name: 'Linha 9')

      expect do
        post_invitation(owner, ws, { email: 'x@fabrica.com', role: 'view', workspace_id: ws_b.id })
      end.not_to(change { invitation_count(ws) })

      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws_b, user: outro_dono) { Invitation.count }).to eq(0)
    end

    it '(4) role "owner": 422 invalid_role e nenhuma linha criada' do
      expect { post_invitation(owner, ws, { email: 'x@fabrica.com', role: 'owner' }) }
        .not_to(change { invitation_count(ws) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('invalid_role')
    end

    it '(5) e-mail de 255 chars: 422 invalid_email e nenhuma linha criada' do
      longo = "#{'a' * 243}@fabrica.com"
      expect(longo.length).to eq(255)

      expect { post_invitation(owner, ws, { email: longo, role: 'view' }) }
        .not_to(change { invitation_count(ws) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('invalid_email')
    end
  end

  describe 'revogação (2.4)' do
    it 'o dono revoga um convite pendente (204) e a linha some' do
      post_invitation(owner, ws, { email: 'joao@fabrica.com', role: 'view' })
      id = JSON.parse(response.body)['id']

      expect { delete "/api/v1/invitations/#{id}", headers: headers_for(owner, ws) }
        .to change { invitation_count(ws) }.from(1).to(0)
      expect(response).to have_http_status(:no_content)
    end

    it 'membro edit revogando: 403 e o convite permanece' do
      post_invitation(owner, ws, { email: 'joao@fabrica.com', role: 'view' })
      id = JSON.parse(response.body)['id']
      add_member(ws, editor, 'edit')

      expect { delete "/api/v1/invitations/#{id}", headers: headers_for(editor, ws) }
        .not_to(change { invitation_count(ws) })
      expect(response).to have_http_status(:forbidden)
    end

    it 'convite de OUTRO workspace: 404 (a RLS esconde a linha), não 403' do
      outro_dono = create(:user, email: 'dono.b@fabrica.com')
      ws_b = make_workspace(owner: outro_dono, name: 'Linha 9')
      pessoa_b = in_workspace(ws_b, user: outro_dono) do
        Person.create!(name: 'Dono B', email: outro_dono.email, user_id: outro_dono.id)
      end
      convite_b = in_workspace(ws_b, user: outro_dono) do
        Invitation.create!(email: 'alheio@fabrica.com', role: 'view', created_by_person: pessoa_b)
      end

      delete "/api/v1/invitations/#{convite_b.id}", headers: headers_for(owner, ws)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('invitation_not_found')
    end
  end
end
