# frozen_string_literal: true

require 'rails_helper'

# authorization-policies G3 (tarefas 3.1, 3.2, 3.5, adaptadas pela decisão de
# execução 8 do EXECUCAO.md): as invariantes 4 e 5 da §4.1 PROVADAS no banco,
# por SQL cru — o model pode ser burlado; a constraint, não.
#
# O esquema da Onda 1 é mais forte que o desenho original da change: o dono é a
# coluna `workspaces.owner_user_id` (exatamente um por construção), imutável por
# trigger + REVOKE de coluna, e o trigger `memberships_owner_is_not_member`
# impede a linha de membership do dono — então o índice único parcial
# `(workspace_id) WHERE role='owner'` é dispensável: `'owner'` NEM EXISTE no
# enum. As tentativas de mutação de `owner_user_id` (como app E como papel
# privilegiado) já são provadas em `spec/tenancy/schema_constraints_spec.rb`
# ("imutabilidade de owner_user_id"); aqui ficam as provas que faltavam.
RSpec.describe 'Invariantes de autorização no banco (§4.1 inv. 4 e 5)', :tenancy do
  let(:conn)  { ActiveRecord::Base.connection }
  let(:owner) { create(:user) }
  let(:ws)    { make_workspace(owner: owner) }

  def q(value) = conn.quote(value)

  describe 'inv. 5 — exatamente um dono, sem caminho de transferência' do
    it "papel 'owner' não é representável no enum membership_role" do
      bruno = create(:user)
      add_member(ws, bruno, 'edit')

      expect do
        in_workspace(ws) do
          conn.execute("UPDATE memberships SET role = 'owner' WHERE user_id = #{q(bruno.id)}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum membership_role/)
    end

    it 'o dono não vira linha de membership (trigger memberships_owner_is_not_member)' do
      person_id = in_workspace(ws) do
        Person.create!(name: owner.name, email: owner.email, user_id: owner.id).id
      end

      expect do
        in_workspace(ws) do
          conn.execute(
            'INSERT INTO memberships (workspace_id, user_id, person_id, role) ' \
            "VALUES (#{q(ws.id)}, #{q(owner.id)}, #{q(person_id)}, 'edit')"
          )
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /não pode ser membro/)
    end

    it 'os mecanismos moram no catálogo do Postgres, não no model' do
      triggers = conn.select_values(<<~SQL)
        SELECT tgname FROM pg_trigger
        WHERE tgname IN ('workspaces_owner_immutable', 'memberships_owner_is_not_member')
      SQL
      expect(triggers).to contain_exactly('workspaces_owner_immutable', 'memberships_owner_is_not_member')

      # Camada de privilégio de coluna (roles.sql): o runtime não tem UPDATE de
      # owner_user_id — só das colunas mutáveis.
      pode_owner = conn.select_value(
        "SELECT has_column_privilege('robotrack_app', 'workspaces', 'owner_user_id', 'UPDATE')"
      )
      pode_name = conn.select_value(
        "SELECT has_column_privilege('robotrack_app', 'workspaces', 'name', 'UPDATE')"
      )
      expect(pode_owner).to be(false)
      expect(pode_name).to be(true)
    end
  end

  describe 'inv. 4 — notifications só muda read/read_at pós-insert' do
    it 'trigger de colunas rejeita mudança de message mesmo para o dono (3.3)' do
      pending 'bloqueada por in-app-notifications — a tabela notifications ainda não existe; ' \
              'o trigger BEFORE UPDATE, o CHECK de 500 chars e o DEFAULT read=false entram na migration daquela change'
      raise 'implementar quando in-app-notifications criar a tabela'
    end
  end
end
