# frozen_string_literal: true

require 'rails_helper'

# code-only-invites §"Aceite/preview por código" (era workspace-invitations
# §"Consumo atômico" e §"Criação ou casamento de Person", tarefas 3.1–3.4).
#
# O aceite e o preview passam a ser EXCLUSIVAMENTE por CÓDIGO — o link por token
# foi removido. As seis condições da invariante 6 continuam idênticas (o
# `consume` é o mesmo); muda só o localizador da linha (por código + e-mail).
# Cada condição tem AQUI o seu código próprio: um `422` genérico reprovaria, o
# cliente precisa distinguir "expirou" de "e-mail errado".
RSpec.describe 'Aceite de convite (por código)', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:joao)  { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }

  let(:owner_person) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  # O `short_code` em claro é transiente e só existe no objeto recém-criado.
  def create_invitation(email: 'joao@fabrica.com', role: 'view', **attrs)
    in_workspace(ws) do
      Invitation.create!(email: email, role: role, created_by_person: owner_person, **attrs)
    end
  end

  # Aceite por código: reusa o e-mail do convite como par (o e-mail SUBMETIDO tem
  # de casar o do convite para o lookup prosseguir; a condição 5 depois compara
  # com o e-mail AUTENTICADO). `submitted_email:` permite forçar um par inválido.
  def accept(convite, user, submitted_email: nil, extra: {})
    post '/api/v1/invitations/code/accept',
         params: { code: convite.short_code, email: submitted_email || convite.email }.merge(extra),
         headers: auth_headers(user)
  end

  def memberships_of(workspace)
    in_workspace(workspace) { Membership.all.to_a }
  end

  describe 'aceite bem-sucedido (3.1)' do
    let!(:convite) { create_invitation(role: 'edit') }

    it 'responde 200, cria UMA membership com o papel do convite e marca o convite' do
      accept(convite, joao)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include('workspace_id' => ws.id, 'role' => 'edit')

      memberships = memberships_of(ws)
      expect(memberships.size).to eq(1)
      expect(memberships.first).to have_attributes(role: 'edit', user_id: joao.id, invitation_id: convite.id)

      recarregado = in_workspace(ws) { Invitation.find(convite.id) }
      expect(recarregado.used_at).to be_present
      expect(recarregado.used_by_user_id).to eq(joao.id)
    end

    it 'não exige X-Workspace-Id: o convidado ainda não é membro de nada' do
      accept(convite, joao)
      expect(response).to have_http_status(:ok)
    end

    it 'o papel vem do CONVITE, não do cliente' do
      accept(convite, joao)
      expect(memberships_of(ws).first.role).to eq('edit')
    end
  end

  describe 'as condições da invariante 6 (3.1)' do
    it '(1) código inexistente: 404 invitation_not_found' do
      post '/api/v1/invitations/code/accept',
           params: { code: 'ZZZZZZZZ', email: 'joao@fabrica.com' }, headers: auth_headers(joao)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('invitation_not_found')
    end

    it '(2) convite já usado: 409 invitation_already_used, sem alterar o consumo' do
      convite = create_invitation
      accept(convite, joao)
      expect(response).to have_http_status(:ok)
      antes = in_workspace(ws) { Invitation.find(convite.id) }

      # A segunda tentativa é do PRÓPRIO João: outro usuário com o mesmo e-mail
      # não é representável (índice único total em `users.email`), e um usuário
      # de e-mail diferente pararia antes, na condição 5.
      accept(convite, joao)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('invitation_already_used')
      depois = in_workspace(ws) { Invitation.find(convite.id) }
      expect(depois.used_at.to_i).to eq(antes.used_at.to_i)
      expect(depois.used_by_user_id).to eq(antes.used_by_user_id)
    end

    it '(3) convite expirado: 410 invitation_expired e nenhuma membership' do
      convite = create_invitation(expires_at: 2.days.ago)

      accept(convite, joao)

      expect(response).to have_http_status(:gone)
      expect(JSON.parse(response.body)['error']).to eq('invitation_expired')
      expect(memberships_of(ws)).to be_empty
    end

    it '(5) e-mail autenticado diferente do convite: 403 invitation_email_mismatch' do
      convite = create_invitation(email: 'joao@fabrica.com')
      ana_convidada = create(:user, name: 'Ana Outra', email: 'ana.outra@fabrica.com')

      # O par (código + e-mail do convite) casa, mas a conta autenticada é outra.
      accept(convite, ana_convidada)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('invitation_email_mismatch')
      expect(in_workspace(ws) { Invitation.find(convite.id) }.used_at).to be_nil
      expect(memberships_of(ws)).to be_empty
    end

    it '(6) role no corpo: 422 unexpected_parameter, sem consumir o convite' do
      convite = create_invitation(role: 'view')

      accept(convite, joao, extra: { role: 'edit' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('unexpected_parameter')
      expect(in_workspace(ws) { Invitation.find(convite.id) }.used_at).to be_nil
      expect(memberships_of(ws)).to be_empty
    end

    it 'quem já é membro recebe 409 already_member e o convite fica PENDENTE' do
      add_member(ws, joao, 'edit')
      convite = create_invitation(email: 'joao@fabrica.com', role: 'view')

      accept(convite, joao)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('already_member')
      expect(in_workspace(ws) { Invitation.find(convite.id) }.used_at).to be_nil
      expect(memberships_of(ws).first.role).to eq('edit')
    end

    it 'convite revogado antes do aceite responde 404' do
      convite = create_invitation
      in_workspace(ws) { Invitation.find(convite.id).destroy! }

      accept(convite, joao)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'resolução de Person (3.2 / D-INV-5)' do
    it 'casa com a Person pré-cadastrada e preserva o mesmo person_id' do
      pessoa = in_workspace(ws) { Person.create!(name: 'João Silva', email: 'joao@fabrica.com') }
      convite = create_invitation(email: 'joao@fabrica.com')

      expect { accept(convite, joao) }
        .not_to(change { in_workspace(ws) { Person.count } })

      expect(response).to have_http_status(:ok)
      recarregada = in_workspace(ws) { Person.find(pessoa.id) }
      expect(recarregada.user_id).to eq(joao.id)
      expect(memberships_of(ws).first.person_id).to eq(pessoa.id)
    end

    it 'cria Person nova quando não há correspondência por e-mail' do
      convite = create_invitation(email: 'joao@fabrica.com')

      accept(convite, joao)

      nova = in_workspace(ws) { Person.find_by(email: 'joao@fabrica.com') }
      expect(nova.user_id).to eq(joao.id)
      expect(nova.name).to eq('João Silva')
    end

    it 'Person já vinculada a OUTRO usuário: 409 person_email_conflict, com rollback' do
      outro = create(:user, email: 'outro@fabrica.com')
      in_workspace(ws) { Person.create!(name: 'João Silva', email: 'joao@fabrica.com', user_id: outro.id) }
      convite = create_invitation(email: 'joao@fabrica.com')

      accept(convite, joao)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('person_email_conflict')
      # Rollback completo: convite continua consumível e nada foi criado.
      expect(in_workspace(ws) { Invitation.find(convite.id) }.used_at).to be_nil
      expect(memberships_of(ws)).to be_empty
      expect(in_workspace(ws) { Person.find_by(email: 'joao@fabrica.com') }.user_id).to eq(outro.id)
    end

    it 'casa por e-mail e NUNCA por nome: homônima sem e-mail não é reaproveitada' do
      homonima = in_workspace(ws) { Person.create!(name: 'João Silva', email: nil) }
      convite = create_invitation(email: 'joao@fabrica.com')

      accept(convite, joao)

      expect(response).to have_http_status(:ok)
      nova = in_workspace(ws) { Person.find_by(email: 'joao@fabrica.com') }
      expect(nova.id).not_to eq(homonima.id)
      expect(in_workspace(ws) { Person.find(homonima.id) }.user_id).to be_nil
      # O índice único de nome normalizado (Onda 1) obriga a desambiguar o NOME —
      # o vínculo continua sendo o e-mail.
      expect(nova.name).to eq('João Silva (joao@fabrica.com)')
    end
  end

  describe 'pré-visualização pública por código (3.4 / D5)' do
    let!(:convite) { create_invitation(email: 'joao@fabrica.com', role: 'view') }

    def preview(code, email)
      post '/api/v1/invitations/code/preview', params: { code: code, email: email }
    end

    it 'par correto responde 200 SEM Authorization e devolve só o mínimo' do
      preview(convite.short_code, 'joao@fabrica.com')

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include(
        'workspace_name' => 'Linha 3',
        'role' => 'view',
        'email_masked' => 'j***@fabrica.com',
        'status' => 'pending'
      )
      expect(body.keys).to contain_exactly('workspace_name', 'role', 'email_masked', 'expires_at', 'status')
      expect(response.body).not_to include('joao@fabrica.com')
      expect(response.body).not_to include(ws.id)
    end

    it 'código inexistente: 404 invitation_not_found' do
      preview('ZZZZZZZZ', 'joao@fabrica.com')

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('invitation_not_found')
    end

    it 'distingue expirado de pendente sem exigir login' do
      expirado = create_invitation(email: 'zeca@fabrica.com', expires_at: 1.day.ago)

      preview(expirado.short_code, 'zeca@fabrica.com')

      expect(JSON.parse(response.body)['status']).to eq('expired')
    end

    it 'a listagem continua protegida: GET /api/v1/invitations sem token é 401' do
      get '/api/v1/invitations'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
