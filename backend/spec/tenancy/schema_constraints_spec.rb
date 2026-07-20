# frozen_string_literal: true

require 'rails_helper'
require 'pg'
require 'securerandom'

# Guarda de esquema das tabelas de tenancy (tarefa 2.6).
#
# Cada constraint de 2.1–2.5 é provada CONTORNANDO o ActiveRecord, por SQL cru —
# porque é exatamente por esse caminho (console, relatório com SQL, importador)
# que ela vai ser exercida em produção. O model pode ser burlado; a constraint
# no banco, não.
#
# As inserções felizes já vêm com o contexto de tenant setado (`set_config`
# local à transação), o que é inócuo agora (sem RLS) e continua correto quando o
# G3 ligar a RLS.
RSpec.describe 'Constraints de esquema das tabelas de tenancy', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:owner)  { create(:user) }
  let(:owner2) { create(:user) }
  let(:ws_a)   { SecureRandom.uuid }
  let(:ws_b)   { SecureRandom.uuid }

  def q(value)
    conn.quote(value)
  end

  # Abre transação e emite o contexto de tenant via SET LOCAL, como o Tenant.with
  # do G3 fará. Uma inserção que deva falhar levanta e a transação é revertida.
  def with_ws(ws_id, user_id: nil)
    conn.transaction do
      conn.execute("SELECT set_config('app.current_workspace_id', #{q(ws_id)}, true)")
      conn.execute("SELECT set_config('app.current_user_id', #{q(user_id)}, true)") if user_id
      yield
    end
  end

  def insert_workspace(id:, owner_id:, name: 'Workspace')
    with_ws(id, user_id: owner_id) do
      conn.execute(
        "INSERT INTO workspaces (id, name, owner_user_id) " \
        "VALUES (#{q(id)}, #{q(name)}, #{q(owner_id)})"
      )
    end
  end

  def insert_person(ws_id:, name:, email: nil, user_id: nil, id: SecureRandom.uuid)
    with_ws(ws_id) do
      conn.execute(
        "INSERT INTO people (id, workspace_id, name, email, user_id) " \
        "VALUES (#{q(id)}, #{q(ws_id)}, #{q(name)}, #{email ? q(email) : 'NULL'}, " \
        "#{user_id ? q(user_id) : 'NULL'})"
      )
    end
    id
  end

  # ---- 2.1 workspaces --------------------------------------------------------

  describe 'workspaces (2.1)' do
    it 'aceita id fornecido pelo cliente, sem substituir por gen_random_uuid()' do
      insert_workspace(id: ws_a, owner_id: owner.id)
      persisted = with_ws(ws_a, user_id: owner.id) do
        conn.select_value("SELECT id FROM workspaces WHERE owner_user_id = #{q(owner.id)}")
      end
      expect(persisted).to eq(ws_a)
    end

    it 'rejeita segundo workspace para o mesmo dono (índice único)' do
      insert_workspace(id: ws_a, owner_id: owner.id)
      expect { insert_workspace(id: ws_b, owner_id: owner.id) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_workspaces_on_owner_user_id/)
      count = with_ws(ws_a, user_id: owner.id) do
        conn.select_value("SELECT count(*) FROM workspaces WHERE owner_user_id = #{q(owner.id)}")
      end
      expect(count).to eq(1)
    end

    it 'não tem coluna responsibles' do
      cols = conn.select_values(
        "SELECT column_name FROM information_schema.columns WHERE table_name = 'workspaces'"
      )
      expect(cols).not_to include('responsibles')
    end
  end

  # ---- 2.2 people ------------------------------------------------------------

  describe 'people (2.2)' do
    before { insert_workspace(id: ws_a, owner_id: owner.id) }

    it 'cria pessoa sem conta (user_id e email NULL)' do
      pid = insert_person(ws_id: ws_a, name: 'Cláudio Terceirizado')
      row = with_ws(ws_a) { conn.select_one("SELECT user_id, email FROM people WHERE id = #{q(pid)}") }
      expect(row['user_id']).to be_nil
      expect(row['email']).to be_nil
    end

    it 'rejeita o sentinela "Não Atribuído" em qualquer grafia (CHECK)' do
      ['Não Atribuído', 'nao atribuido', 'NÃO ATRIBUÍDO', '  Não Atribuído '].each do |name|
        expect { insert_person(ws_id: ws_a, name: name) }
          .to raise_error(ActiveRecord::StatementInvalid, /people_name_not_sentinel/),
              "esperado CHECK barrar #{name.inspect}"
      end
    end

    it 'aceita nome válido que apenas contém a palavra ("Ana Atribuído")' do
      expect { insert_person(ws_id: ws_a, name: 'Ana Atribuído') }.not_to raise_error
    end

    it 'rejeita nome duplicado normalizado no mesmo workspace' do
      insert_person(ws_id: ws_a, name: 'João Souza')
      expect { insert_person(ws_id: ws_a, name: ' joão souza ') }
        .to raise_error(ActiveRecord::RecordNotUnique, /normalized_name/)
    end

    it 'permite o mesmo nome em workspaces diferentes' do
      insert_workspace(id: ws_b, owner_id: owner2.id)
      insert_person(ws_id: ws_a, name: 'João Souza')
      expect { insert_person(ws_id: ws_b, name: 'João Souza') }.not_to raise_error
    end

    it 'casa e-mail case-insensitive (citext) — unicidade por workspace' do
      insert_person(ws_id: ws_a, name: 'Ana Lima', email: 'Ana@Fabrica.com')
      expect { insert_person(ws_id: ws_a, name: 'Ana Clone', email: 'ana@fabrica.com') }
        .to raise_error(ActiveRecord::RecordNotUnique, /email/)
    end
  end

  # ---- 2.3 memberships -------------------------------------------------------

  describe 'memberships (2.3)' do
    let(:member) { create(:user) }

    before do
      insert_workspace(id: ws_a, owner_id: owner.id)
      insert_workspace(id: ws_b, owner_id: owner2.id)
    end

    def insert_membership(ws_id:, user_id:, person_id:, role: 'edit')
      with_ws(ws_id, user_id: user_id) do
        conn.execute(
          "INSERT INTO memberships (workspace_id, user_id, person_id, role) " \
          "VALUES (#{q(ws_id)}, #{q(user_id)}, #{q(person_id)}, #{q(role)})"
        )
      end
    end

    it 'rejeita UPDATE de role para owner (valor inexistente no enum)' do
      person = insert_person(ws_id: ws_a, name: 'Membro Um', user_id: member.id)
      insert_membership(ws_id: ws_a, user_id: member.id, person_id: person)
      expect do
        with_ws(ws_a) { conn.execute("UPDATE memberships SET role = 'owner' WHERE user_id = #{q(member.id)}") }
      end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum membership_role/)
    end

    it 'rejeita person_id de outro workspace (FK composta)' do
      person_b = insert_person(ws_id: ws_b, name: 'Alheia', user_id: member.id)
      expect { insert_membership(ws_id: ws_a, user_id: member.id, person_id: person_b) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_memberships_person_same_workspace/)
    end

    it 'rejeita segunda membership para o mesmo (workspace, usuário)' do
      person = insert_person(ws_id: ws_a, name: 'Membro Dois', user_id: member.id)
      insert_membership(ws_id: ws_a, user_id: member.id, person_id: person)
      person2 = insert_person(ws_id: ws_a, name: 'Outro Nome', email: 'outro@x.com')
      expect { insert_membership(ws_id: ws_a, user_id: member.id, person_id: person2) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_memberships_on_workspace_id_and_user_id/)
    end

    # ---- 2.4 dono não é membro ----
    it 'rejeita membership cujo user_id é o dono do workspace (trigger)' do
      owner_person = insert_person(ws_id: ws_a, name: 'Dono Pessoa', user_id: owner.id)
      expect { insert_membership(ws_id: ws_a, user_id: owner.id, person_id: owner_person) }
        .to raise_error(ActiveRecord::StatementInvalid, /não pode ser membro/)
    end
  end

  # ---- 2.5 imutabilidade do dono --------------------------------------------

  describe 'imutabilidade de owner_user_id (2.5)' do
    before { insert_workspace(id: ws_a, owner_id: owner.id) }

    it 'nega ao papel da aplicação por privilégio de coluna' do
      expect do
        with_ws(ws_a) { conn.execute("UPDATE workspaces SET owner_user_id = #{q(owner2.id)} WHERE id = #{q(ws_a)}") }
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied for (column|table)/)
    end

    it 'permite ao app atualizar apenas o name' do
      expect do
        with_ws(ws_a) { conn.execute("UPDATE workspaces SET name = 'Renomeado' WHERE id = #{q(ws_a)}") }
      end.not_to raise_error
      name = with_ws(ws_a) { conn.select_value("SELECT name FROM workspaces WHERE id = #{q(ws_a)}") }
      expect(name).to eq('Renomeado')
    end

    it 'nega ao papel privilegiado pela trigger workspaces_owner_immutable' do
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      mconn = PG.connect(
        host: cfg[:host] || 'localhost',
        dbname: cfg[:database],
        user: ENV.fetch('MIGRATOR_DB_USER', 'robotrack_migrator'),
        password: ENV.fetch('MIGRATOR_DB_PASSWORD', 'mig_dev_pw')
      )
      # Com FORCE RLS, até o dono das tabelas é sujeito à política: sem contexto,
      # o migrator veria 0 linhas e o UPDATE não alcançaria a linha (nem a trigger).
      mconn.exec("SELECT set_config('app.current_workspace_id', #{q(ws_a)}, false)")
      expect do
        mconn.exec("UPDATE workspaces SET owner_user_id = #{q(owner2.id)} WHERE id = #{q(ws_a)}")
      end.to raise_error(PG::RaiseException, /imutável \(§4\.1 inv\. 5\)/)
      # A linha permanece inalterada.
      persisted = mconn.exec("SELECT owner_user_id FROM workspaces WHERE id = #{q(ws_a)}").getvalue(0, 0)
      expect(persisted).to eq(owner.id)
    ensure
      mconn&.close
    end
  end
end
