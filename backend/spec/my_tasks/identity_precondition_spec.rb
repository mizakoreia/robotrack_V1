# frozen_string_literal: true

require 'rails_helper'

# my-tasks-view §1 (D10/D11, D-MTV-2) — a PRÉ-CONDIÇÃO de identidade, provada com os
# services REAIS (bootstrap de workspace-tenancy e aceite de workspace-invitations),
# nunca com factory de `Person`. Se algum deles parar de criar/resolver a `Person`,
# "Minhas Tarefas" volta VAZIA para o usuário e nada acusa — estes specs acusam.
RSpec.describe 'my-tasks-view — pré-condição de identidade (D10)', :tenancy, type: :request do
  def person_in(ws_id, user_id)
    Tenant.with(workspace_id: ws_id, user_id: user_id) do
      Person.find_by(workspace_id: ws_id, user_id: user_id)
    end
  end

  # 1.1 — bootstrap REAL cria a Person do dono.
  describe '1.1 bootstrap real cria a Person do dono' do
    it 'Person(workspace_id, user_id) existe com user_id preenchido (sem factory)' do
      user = create(:user, name: 'Ana Dona', email: 'ana@fabrica.com')
      ws = Workspaces::BootstrapService.new(user: user).call

      person = person_in(ws.id, user.id)
      expect(person).to be_present
      expect(person.user_id).to eq(user.id)
      expect(person.workspace_id).to eq(ws.id)
    end
  end

  # 1.2 — aceite REAL de convite, os DOIS ramos de D-INV-5.
  describe '1.2 aceite real resolve a Person (dois ramos)' do
    let(:owner) { create(:user, name: 'Dona Ana', email: 'dona@fabrica.com') }
    let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
    let(:owner_person) do
      in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
    end

    def create_invitation(email:, role: 'edit')
      in_workspace(ws) { Invitation.create!(email: email, role: role, created_by_person: owner_person) }
    end

    it 'ramo "não casa por e-mail": cria uma Person nova com user_id do convidado' do
      convidado = create(:user, name: 'João Silva', email: 'joao@fabrica.com')
      convite = create_invitation(email: 'joao@fabrica.com')

      post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(convidado)
      expect(response).to have_http_status(:ok)

      person = person_in(ws.id, convidado.id)
      expect(person).to be_present
      expect(person.user_id).to eq(convidado.id)
      expect(person.email).to eq('joao@fabrica.com')
    end

    it 'ramo "casa por e-mail": REUSA a Person já cadastrada (não cria uma segunda)' do
      convidada = create(:user, name: 'Marta', email: 'marta@fabrica.com')
      # o dono já cadastrou "Marta" como responsável (sem conta) ANTES de convidar:
      pre = in_workspace(ws) { Person.create!(name: 'Marta', email: 'marta@fabrica.com', user_id: nil) }
      convite = create_invitation(email: 'marta@fabrica.com')

      expect do
        post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(convidada)
      end.not_to(change { in_workspace(ws) { Person.where(email: 'marta@fabrica.com').count } })
      expect(response).to have_http_status(:ok)

      person = person_in(ws.id, convidada.id)
      expect(person.id).to eq(pre.id)          # a MESMA Person
      expect(person.user_id).to eq(convidada.id) # agora ligada à conta
    end
  end

  # 1.3 — o esquema torna "membro sem Person" inexpressável e não guarda nome de
  # responsável em texto (D11).
  describe '1.3 esquema (D11)' do
    let(:conn) { ActiveRecord::Base.connection }

    it 'memberships.person_id é NOT NULL' do
      col = conn.columns('memberships').find { |c| c.name == 'person_id' }
      expect(col).to be_present
      expect(col.null).to be(false)
    end

    it 'memberships tem FK de person_id para people' do
      fks = conn.execute(<<~SQL).to_a
        SELECT conname FROM pg_constraint
        WHERE conrelid = 'memberships'::regclass AND contype = 'f'
          AND confrelid = 'people'::regclass
      SQL
      expect(fks).not_to be_empty
    end

    it 'nenhuma coluna de texto *responsible*/*assignee_name* em tasks ou task_assignees' do
      %w[tasks task_assignees].each do |tbl|
        textuais = conn.columns(tbl).select do |c|
          c.name =~ /responsible|assignee_name/ && %i[string text].include?(c.type)
        end
        expect(textuais).to be_empty, "coluna de nome de responsável sobrevivente em #{tbl}: #{textuais.map(&:name)}"
      end
    end
  end

  # 1.4 — a asserção NÃO é vácua: com o bootstrap da Person desabilitado por stub, a
  # pré-condição de 1.1 REALMENTE falha (o guard detecta a regressão).
  describe '1.4 o guard detecta a regressão' do
    it 'com ensure_owner_person stubbado, a Person do dono não existe' do
      user = create(:user, name: 'Bia', email: 'bia@fabrica.com')
      allow_any_instance_of(Workspaces::BootstrapService).to receive(:ensure_owner_person)

      ws = Workspaces::BootstrapService.new(user: user).call
      expect(person_in(ws.id, user.id)).to be_nil
    end
  end
end
