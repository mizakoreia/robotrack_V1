# frozen_string_literal: true

require 'rails_helper'
require 'pg'
require 'securerandom'

# workspace-invitations, verificação do grupo 1 (tarefa 1.5).
#
# Cada constraint de 1.2–1.4 é provada CONTORNANDO o ActiveRecord, por SQL cru.
# É o mesmo argumento do spec irmão da Onda 1: o model pode ser burlado por um
# console, um importador ou um relatório; a constraint no banco, não. Se a
# invariante 6 ou 7 só existisse no service, este arquivo não teria nada a dizer.
RSpec.describe 'Constraints de esquema de invitations', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:owner)   { create(:user) }
  let(:owner_b) { create(:user) }
  let(:guest)   { create(:user) }
  let(:ws_a)    { SecureRandom.uuid }
  let(:ws_b)    { SecureRandom.uuid }

  def q(value)
    conn.quote(value)
  end

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

  # Inserção crua de convite, com todos os campos sobrescrevíveis para que cada
  # exemplo negativo altere UM só e o motivo da falha não seja ambíguo.
  def insert_invitation(ws_id:, creator_id:, token: "rt_inv_#{SecureRandom.urlsafe_base64(32)}",
                        email: 'joao@fabrica.com', role: 'view', expires_at: :default,
                        used_at: nil, used_by: nil, id: SecureRandom.uuid)
    expires_sql = expires_at == :default ? "now() + interval '7 days'" : (expires_at.nil? ? 'NULL' : q(expires_at))
    with_ws(ws_id) do
      conn.execute(<<~SQL)
        INSERT INTO invitations
          (id, workspace_id, token, email, role, created_by_person_id, expires_at, used_at, used_by_user_id)
        VALUES
          (#{q(id)}, #{q(ws_id)}, #{q(token)}, #{q(email)}, #{q(role)}::invitation_role,
           #{q(creator_id)}, #{expires_sql}, #{used_at ? q(used_at) : 'NULL'},
           #{used_by ? q(used_by) : 'NULL'})
      SQL
    end
    id
  end

  # Cenário base: WS-A com dono e a Person dele (a criadora dos convites).
  let!(:creator_person) do
    insert_workspace(id: ws_a, owner_id: owner.id)
    insert_person(ws_id: ws_a, name: 'Dona A', email: owner.email.downcase)
  end

  describe 'invariante 7 no banco (1.2)' do
    it 'aceita o convite bem formado, com expires_at 7 dias à frente' do
      insert_invitation(ws_id: ws_a, creator_id: creator_person)

      row = with_ws(ws_a) do
        conn.select_one('SELECT email, role, used_at, used_by_user_id, ' \
                        'EXTRACT(day FROM expires_at - created_at) AS dias FROM invitations')
      end
      expect(row['email']).to eq('joao@fabrica.com')
      expect(row['role']).to eq('view')
      expect(row['used_at']).to be_nil
      expect(row['used_by_user_id']).to be_nil
      expect(row['dias'].to_i).to eq(7)
    end

    it "(1) rejeita role='owner': não é valor representável no enum" do
      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, role: 'owner')
      end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum invitation_role/)
    end

    it '(2) rejeita e-mail com maiúsculas (chk_invitations_email_lowercase)' do
      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'Joao@Fabrica.com')
      end.to raise_error(ActiveRecord::StatementInvalid, /chk_invitations_email_lowercase/)
    end

    it '(3) rejeita e-mail de 255 chars (chk_invitations_email_length)' do
      longo = "#{'a' * 243}@fabrica.com" # 243 + 12 = 255
      expect(longo.length).to eq(255)
      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, email: longo)
      end.to raise_error(ActiveRecord::StatementInvalid, /chk_invitations_email_length/)
    end

    it '(4) rejeita expires_at NULL: convite sem expiração não é representável' do
      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, expires_at: nil)
      end.to raise_error(ActiveRecord::StatementInvalid, /null value in column "expires_at"/)
    end

    it '(5) rejeita criador que pertence a OUTRO workspace (FK composta)' do
      insert_workspace(id: ws_b, owner_id: owner_b.id)
      pessoa_de_b = insert_person(ws_id: ws_b, name: 'Dono B', email: owner_b.email.downcase)

      expect do
        insert_invitation(ws_id: ws_a, creator_id: pessoa_de_b)
      end.to raise_error(ActiveRecord::StatementInvalid, /fk_invitations_creator_in_workspace/)
    end

    it '(6) rejeita o estado meio-consumido (chk_invitations_consumption)' do
      id = insert_invitation(ws_id: ws_a, creator_id: creator_person)

      expect do
        with_ws(ws_a) do
          conn.execute("UPDATE invitations SET used_at = now() WHERE id = #{q(id)}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /chk_invitations_consumption/)
    end

    it 'rejeita o segundo convite PENDENTE para o mesmo e-mail no mesmo workspace' do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'ana@fabrica.com')

      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'ana@fabrica.com')
      end.to raise_error(ActiveRecord::RecordNotUnique, /index_invitations_pending_unique_per_email/)
    end

    it 'aceita novo convite para o e-mail cujo convite anterior já foi consumido' do
      primeiro = insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'ana@fabrica.com')
      with_ws(ws_a) do
        conn.execute("UPDATE invitations SET used_at = now(), used_by_user_id = #{q(guest.id)} " \
                     "WHERE id = #{q(primeiro)}")
      end

      expect do
        insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'ana@fabrica.com')
      end.not_to raise_error
    end
  end

  describe 'invariante 6 no banco (1.3)' do
    let(:person_convidado) { insert_person(ws_id: ws_a, name: 'João Silva', email: 'joao@fabrica.com') }

    def insert_membership(ws_id:, user_id:, person_id:, invitation_id:, role: 'view')
      with_ws(ws_id) do
        conn.execute(<<~SQL)
          INSERT INTO memberships (id, workspace_id, user_id, person_id, role, invitation_id)
          VALUES (#{q(SecureRandom.uuid)}, #{q(ws_id)}, #{q(user_id)}, #{q(person_id)},
                  #{q(role)}::membership_role, #{q(invitation_id)})
        SQL
      end
    end

    it 'rejeita a SEGUNDA membership derivada do mesmo convite (índice único parcial)' do
      convite = insert_invitation(ws_id: ws_a, creator_id: creator_person)
      pessoa = person_convidado
      insert_membership(ws_id: ws_a, user_id: guest.id, person_id: pessoa, invitation_id: convite)

      outro = create(:user)
      outra_pessoa = insert_person(ws_id: ws_a, name: 'Outra', email: 'outra@fabrica.com')

      expect do
        insert_membership(ws_id: ws_a, user_id: outro.id, person_id: outra_pessoa, invitation_id: convite)
      end.to raise_error(ActiveRecord::RecordNotUnique, /idx_memberships_one_per_invitation/)
    end

    it 'não impede memberships SEM convite (invitation_id NULL) de coexistirem' do
      p1 = insert_person(ws_id: ws_a, name: 'Sem Convite 1', email: 'sc1@fabrica.com')
      p2 = insert_person(ws_id: ws_a, name: 'Sem Convite 2', email: 'sc2@fabrica.com')
      u1 = create(:user)
      u2 = create(:user)

      with_ws(ws_a) do
        conn.execute("INSERT INTO memberships (id, workspace_id, user_id, person_id, role) " \
                     "VALUES (#{q(SecureRandom.uuid)}, #{q(ws_a)}, #{q(u1.id)}, #{q(p1)}, 'view')")
        conn.execute("INSERT INTO memberships (id, workspace_id, user_id, person_id, role) " \
                     "VALUES (#{q(SecureRandom.uuid)}, #{q(ws_a)}, #{q(u2.id)}, #{q(p2)}, 'view')")
      end

      count = with_ws(ws_a) { conn.select_value('SELECT count(*) FROM memberships').to_i }
      expect(count).to eq(2)
    end

    it 'impede apagar um convite que já originou membership (ON DELETE RESTRICT)' do
      convite = insert_invitation(ws_id: ws_a, creator_id: creator_person)
      insert_membership(ws_id: ws_a, user_id: guest.id, person_id: person_convidado, invitation_id: convite)

      expect do
        with_ws(ws_a) { conn.execute("DELETE FROM invitations WHERE id = #{q(convite)}") }
      end.to raise_error(ActiveRecord::InvalidForeignKey, /fk_memberships_invitation/)
    end
  end

  describe 'RLS e acesso por token (1.4)' do
    let!(:token_a) { "rt_inv_#{SecureRandom.urlsafe_base64(32)}" }

    before do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, token: token_a)
    end

    it 'não devolve convite de WS-B no contexto de WS-A' do
      insert_workspace(id: ws_b, owner_id: owner_b.id)
      pessoa_b = insert_person(ws_id: ws_b, name: 'Dono B', email: owner_b.email.downcase)
      insert_invitation(ws_id: ws_b, creator_id: pessoa_b, email: 'alheio@fabrica.com')

      emails = with_ws(ws_a) { conn.select_values('SELECT email FROM invitations') }
      expect(emails).to eq(['joao@fabrica.com'])
    end

    it 'sem contexto nenhum, a listagem é vazia (fail-closed)' do
      linhas = conn.transaction { conn.select_values('SELECT token FROM invitations') }
      expect(linhas).to be_empty
    end

    it 'invitation_by_token devolve a linha por token exato, sem workspace corrente' do
      row = conn.transaction { conn.select_one("SELECT * FROM invitation_by_token(#{q(token_a)})") }
      expect(row['email']).to eq('joao@fabrica.com')
      expect(row['workspace_id']).to eq(ws_a)
    end

    it 'invitation_by_token com token inexistente devolve vazio, não erro' do
      rows = conn.transaction { conn.select_all("SELECT * FROM invitation_by_token('rt_inv_NAO_EXISTE')") }
      expect(rows.count).to eq(0)
    end

    it 'a função NÃO é uma porta de listagem: um token não revela os outros' do
      insert_invitation(ws_id: ws_a, creator_id: creator_person, email: 'outro@fabrica.com')

      rows = conn.transaction { conn.select_all("SELECT * FROM invitation_by_token(#{q(token_a)})") }
      expect(rows.count).to eq(1)
      expect(rows.first['email']).to eq('joao@fabrica.com')
    end

    it 'a variável de token não sobrevive à transação (SET LOCAL)' do
      conn.transaction { conn.select_all("SELECT * FROM invitation_by_token(#{q(token_a)})") }

      depois = conn.transaction { conn.select_values('SELECT token FROM invitations') }
      expect(depois).to be_empty
    end

    it 'a leitura por token NÃO habilita escrita fora do workspace (WITH CHECK puro)' do
      expect do
        conn.transaction do
          conn.execute("SELECT set_config('app.invitation_token', #{q(token_a)}, true)")
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
