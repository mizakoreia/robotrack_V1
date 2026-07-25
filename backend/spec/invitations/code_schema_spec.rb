# frozen_string_literal: true

require 'rails_helper'
require 'pg'
require 'securerandom'

# invite-by-code G1.4 — as garantias do código curto que moram no BANCO, provadas
# por SQL cru (contornando o ActiveRecord), como o spec irmão da Onda de
# workspace-invitations. O lookup por código espelha `invitation_by_token`: acesso
# por HASH exato, nunca listagem, sem BYPASSRLS, fail-closed sem a GUC.
RSpec.describe 'Constraints e RLS do código de convite', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:owner)   { create(:user) }
  let(:owner_b) { create(:user) }
  let(:ws_a)    { SecureRandom.uuid }
  let(:ws_b)    { SecureRandom.uuid }

  def q(value) = conn.quote(value)

  def with_ws(ws_id, user_id: nil)
    conn.transaction do
      conn.execute("SELECT set_config('app.current_workspace_id', #{q(ws_id)}, true)")
      conn.execute("SELECT set_config('app.current_user_id', #{q(user_id)}, true)") if user_id
      yield
    end
  end

  def insert_workspace(id:, owner_id:, name: 'Workspace')
    with_ws(id, user_id: owner_id) do
      conn.execute("INSERT INTO workspaces (id, name, owner_user_id) " \
                   "VALUES (#{q(id)}, #{q(name)}, #{q(owner_id)})")
    end
  end

  def insert_person(ws_id:, name:, email: nil, id: SecureRandom.uuid)
    with_ws(ws_id) do
      conn.execute("INSERT INTO people (id, workspace_id, name, email) " \
                   "VALUES (#{q(id)}, #{q(ws_id)}, #{q(name)}, #{email ? q(email) : 'NULL'})")
    end
    id
  end

  # Inserção crua de convite COM código: cada campo sobrescrevível para que o
  # exemplo negativo altere um só. `code_hash: :none` → convite via link puro.
  def insert_invitation(ws_id:, creator_id:, email: 'joao@fabrica.com', role: 'view',
                        token: "rt_inv_#{SecureRandom.urlsafe_base64(32)}",
                        code_hash: :auto, id: SecureRandom.uuid)
    hash_sql =
      case code_hash
      when :auto then q(SecureRandom.hex(32))
      when :none then 'NULL'
      else q(code_hash)
      end
    with_ws(ws_id) do
      conn.execute(<<~SQL)
        INSERT INTO invitations
          (id, workspace_id, token, email, role, created_by_person_id, expires_at,
           code_hash, code_expires_at)
        VALUES
          (#{q(id)}, #{q(ws_id)}, #{q(token)}, #{q(email)}, #{q(role)}::invitation_role,
           #{q(creator_id)}, now() + interval '7 days',
           #{hash_sql}, #{hash_sql == 'NULL' ? 'NULL' : "now() + interval '48 hours'"})
      SQL
    end
    id
  end

  let!(:creator_person) do
    insert_workspace(id: ws_a, owner_id: owner.id)
    insert_person(ws_id: ws_a, name: 'Dona A', email: owner.email.downcase)
  end

  describe 'unicidade do code_hash (índice único parcial)' do
    it 'rejeita dois convites com o MESMO code_hash' do
      hash = SecureRandom.hex(32)
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'a@fabrica.com', code_hash: hash)

      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'b@fabrica.com', code_hash: hash)
      end.to raise_error(ActiveRecord::RecordNotUnique, /index_invitations_on_code_hash/)
    end

    it 'permite múltiplos convites SEM código (code_hash NULL coexistem)' do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'a@fabrica.com', code_hash: :none)
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'b@fabrica.com', code_hash: :none)

      count = with_ws(ws_a) { conn.select_value('SELECT count(*) FROM invitations').to_i }
      expect(count).to eq(2)
    end
  end

  describe 'invitation_by_code (lookup por hash, sem workspace corrente)' do
    let(:hash_a) { SecureRandom.hex(32) }

    before do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, code_hash: hash_a)
    end

    it 'devolve a linha por hash exato, sem nenhum workspace setado' do
      row = conn.transaction { conn.select_one("SELECT * FROM invitation_by_code(#{q(hash_a)})") }
      expect(row['email']).to eq('joao@fabrica.com')
      expect(row['workspace_id']).to eq(ws_a)
    end

    it 'hash inexistente devolve vazio, não erro' do
      rows = conn.transaction { conn.select_all("SELECT * FROM invitation_by_code(#{q(SecureRandom.hex(32))})") }
      expect(rows.count).to eq(0)
    end

    it 'NÃO é porta de listagem: um hash não revela os outros convites' do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'outro@fabrica.com',
                        code_hash: SecureRandom.hex(32))

      rows = conn.transaction { conn.select_all("SELECT * FROM invitation_by_code(#{q(hash_a)})") }
      expect(rows.count).to eq(1)
      expect(rows.first['email']).to eq('joao@fabrica.com')
    end

    it 'a GUC do código não sobrevive à transação (SET LOCAL)' do
      conn.transaction { conn.select_all("SELECT * FROM invitation_by_code(#{q(hash_a)})") }

      depois = conn.transaction { conn.select_values('SELECT code_hash FROM invitations') }
      expect(depois).to be_empty
    end
  end

  describe 'RLS por código: fail-closed e sem vazamento cross-tenant' do
    let(:hash_a) { SecureRandom.hex(32) }

    before { insert_invitation(ws_id: ws_a, creator_id: creator_person, code_hash: hash_a) }

    it 'setando só app.invitation_code_hash, vê APENAS a linha daquele hash' do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'outro@fabrica.com',
                        code_hash: SecureRandom.hex(32))

      emails = conn.transaction do
        conn.execute("SELECT set_config('app.invitation_code_hash', #{q(hash_a)}, true)")
        conn.select_values('SELECT email FROM invitations')
      end
      expect(emails).to eq(['joao@fabrica.com'])
    end

    it 'sem GUC de workspace nem de código, a listagem é vazia (fail-closed)' do
      linhas = conn.transaction { conn.select_values('SELECT code_hash FROM invitations') }
      expect(linhas).to be_empty
    end

    it 'convite de WS-B não vaza no contexto de WS-A sem conhecer o código' do
      insert_workspace(id: ws_b, owner_id: owner_b.id)
      pessoa_b = insert_person(ws_id: ws_b, name: 'Dono B', email: owner_b.email.downcase)
      insert_invitation(ws_id: ws_b, creator_id: pessoa_b, email: 'alheio@fabrica.com',
                        code_hash: SecureRandom.hex(32))

      emails = with_ws(ws_a) { conn.select_values('SELECT email FROM invitations') }
      expect(emails).to eq(['joao@fabrica.com'])
    end

    it 'ler por código NÃO habilita escrever (WITH CHECK puro de workspace)' do
      expect do
        conn.transaction do
          conn.execute("SELECT set_config('app.invitation_code_hash', #{q(hash_a)}, true)")
          conn.execute(<<~SQL)
            INSERT INTO invitations
              (id, workspace_id, token, email, role, created_by_person_id, expires_at)
            VALUES (#{q(SecureRandom.uuid)}, #{q(ws_a)}, 'rt_inv_forjado', 'x@fabrica.com',
                    'view', #{q(creator_person)}, now() + interval '7 days')
          SQL
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end
end
