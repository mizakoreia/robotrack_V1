# frozen_string_literal: true

require 'rails_helper'

# workspace-core §"Bootstrap" + workspace-membership §"Resolução" (tarefa 5.4).
RSpec.describe 'Bootstrap e resolução de Person', :tenancy do
  # Lê dentro do contexto do workspace (a RLS escopa people/workspaces).
  def in_ws(workspace_id, user_id)
    Tenant.with(workspace_id: workspace_id, user_id: user_id) { yield }
  end

  # Conta os workspaces de um dono com contexto de usuário (a política de
  # controle de `workspaces` deixa ver os que ele possui).
  def owner_workspace_count(user)
    ActiveRecord::Base.transaction do
      Tenant.set_user!(user.id)
      Workspace.where(owner_user_id: user.id).count
    end
  end

  describe Workspaces::BootstrapService do
    let(:user) { create(:user, name: 'Maria Silva', email: 'maria@exemplo.com') }

    it 'cria o workspace e a Person do dono no primeiro login' do
      ws = described_class.new(user: user).call

      expect(ws.name).to eq('Workspace de Maria Silva')
      expect(ws.owner_user_id).to eq(user.id)

      person = in_ws(ws.id, user.id) { Person.find_by(user_id: user.id) }
      expect(person.name).to eq('Maria Silva')
      expect(person.email).to eq('maria@exemplo.com')
    end

    it 'é idempotente: logins repetidos não duplicam nada' do
      described_class.new(user: user).call
      described_class.new(user: user).call
      ws = described_class.new(user: user).call

      expect(owner_workspace_count(user)).to eq(1)
      count = in_ws(ws.id, user.id) { Person.count }
      expect(count).to eq(1)
    end

    it 'dois logins simultâneos criam um único workspace, sem RecordNotUnique' do
      errors = []
      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.new(user: user).call
          rescue StandardError => e
            errors << e
          end
        end
      end
      threads.each(&:join)

      # A mensagem importa: sem ela, a falha era só "esperava vazio", e a exceção
      # que explicava a corrida ficava engolida pelo `rescue` acima.
      expect(errors).to be_empty, errors.map { |e| "#{e.class}: #{e.message}" }.join("\n")
      expect(owner_workspace_count(user)).to eq(1)
    end

    it 'cai para a parte local do e-mail quando o display_name é vazio' do
      # identity-and-auth (D4.6) impõe CHECK `char_length(btrim(name)) >= 2`: um
      # nome vazio no banco deixou de ser possível (era simulado por
      # update_column). O fallback do BootstrapService segue defensivo; aqui o
      # display_name vazio é simulado no objeto, sem violar o CHECK.
      googler = create(:user, name: 'Conta Google', email: 'joao.pereira@fabrica.com.br')
      allow(googler).to receive(:display_name).and_return('')

      ws = described_class.new(user: googler).call
      expect(ws.name).to eq('Workspace de joao.pereira')
    end

    it 'emite workspace.bootstrapped e não semeia catálogo (só a Person do dono)' do
      eventos = []
      callback = ->(*args) { eventos << ActiveSupport::Notifications::Event.new(*args) }

      ws = ActiveSupport::Notifications.subscribed(callback, 'workspace.bootstrapped') do
        described_class.new(user: user).call
      end

      expect(eventos.size).to eq(1)
      expect(eventos.first.payload[:workspace_id]).to eq(ws.id)
      expect(in_ws(ws.id, user.id) { Person.count }).to eq(1) # nada além do dono
    end
  end

  describe People::ResolveService do
    let(:owner) { create(:user) }
    let(:ws) { make_workspace(owner: owner) }

    it 'casa Person pré-existente sem conta e preenche user_id na MESMA linha' do
      ana = create(:user, email: 'ana@fabrica.com', name: 'Ana Lima')
      person_id = in_ws(ws.id, owner.id) do
        Person.create!(name: 'Ana Lima', email: 'ana@fabrica.com').id
      end
      antes = in_ws(ws.id, owner.id) { Person.count }

      resolved = described_class.new(
        workspace_id: ws.id, email: 'ana@fabrica.com', name: 'Ana Lima', user_id: ana.id
      ).call

      expect(resolved.id).to eq(person_id)      # mesma linha, mesmo person_id
      expect(resolved.user_id).to eq(ana.id)    # user_id preenchido
      expect(in_ws(ws.id, owner.id) { Person.count }).to eq(antes) # não duplicou
    end

    it 'cria nova Person quando não há correspondência de e-mail' do
      carlos = create(:user, email: 'carlos@fabrica.com')
      resolved = described_class.new(
        workspace_id: ws.id, email: 'carlos@fabrica.com', name: 'Carlos', user_id: carlos.id
      ).call

      expect(resolved).to be_persisted
      expect(resolved.user_id).to eq(carlos.id)
      expect(resolved.email).to eq('carlos@fabrica.com')
    end

    it 'casa e-mail case-insensitive (citext), sem criar segunda Person' do
      in_ws(ws.id, owner.id) { Person.create!(name: 'Ana', email: 'Ana@Fabrica.com') }
      ana = create(:user, email: 'ana@fabrica.com')

      resolved = described_class.new(workspace_id: ws.id, email: 'ana@fabrica.com', user_id: ana.id).call

      expect(resolved.user_id).to eq(ana.id)
      expect(in_ws(ws.id, owner.id) { Person.where("lower(email::text) = 'ana@fabrica.com'").count }).to eq(1)
    end

    it 'nunca cruza workspace: e-mail existente em WS-B não é reutilizado em WS-A' do
      ws_b = make_workspace
      in_ws(ws_b.id, ws_b.owner.id) { Person.create!(name: 'Ana', email: 'ana@fabrica.com') }
      ana = create(:user, email: 'ana@fabrica.com')

      resolved = described_class.new(workspace_id: ws.id, email: 'ana@fabrica.com', user_id: ana.id).call

      # Nova Person em WS-A (make_workspace não semeia Person do dono); a de WS-B intacta.
      expect(in_ws(ws.id, owner.id) { Person.count }).to eq(1) # só a Ana nova
      expect(in_ws(ws_b.id, ws_b.owner.id) { Person.find_by(email: 'ana@fabrica.com').user_id }).to be_nil
      expect(resolved.workspace_id).to eq(ws.id)
    end

    it 'remover a membership preserva a Person e o histórico' do
      membro = create(:user)
      person, membership = in_ws(ws.id, owner.id) do
        p = Person.create!(name: 'Membro', email: membro.email, user_id: membro.id)
        m = Membership.create!(workspace_id: ws.id, user: membro, person: p, role: 'edit')
        [p, m]
      end

      in_ws(ws.id, owner.id) { Membership.find(membership.id).destroy! }

      still = in_ws(ws.id, owner.id) { Person.find_by(id: person.id) }
      expect(still).to be_present
      expect(still.user_id).to eq(membro.id)
    end
  end
end
