# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'

# workspace-settings G1 (§3.9/§3.11, D-SENTINEL/D-PERSON-DEL/D2) — as invariantes NO
# BANCO: índice único PARCIAL de nome ativo, CHECK de nome não-vazio, trigger que
# recusa arquivar quem tem membership ativa, e a RLS de workspace_backups. Provadas
# contornando o ActiveRecord (SQL cru), porque é por esse caminho que serão
# exercidas.
RSpec.describe 'workspace-settings — esquema (G1)', :tenancy, type: :request do
  let(:conn)  { ActiveRecord::Base.connection }
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def q(v) = conn.quote(v)

  describe 'índice único parcial de nome (D-SENTINEL)' do
    it 'nome ativo duplicado (ignorando caixa) é recusado; arquivar libera o mesmo nome' do
      in_workspace(ws) { Person.create!(name: 'Ana') }
      # cada operação que levanta vai no SEU bloco (a transação abortada não vaza)
      expect { in_workspace(ws) { Person.create!(name: 'ana') } }.to raise_error(ActiveRecord::RecordNotUnique)

      in_workspace(ws) do
        conn.execute("UPDATE people SET archived_at = now() WHERE workspace_id = #{q(ws.id)} AND lower(btrim(name)) = 'ana'")
        Person.create!(name: 'Ana') # com a anterior arquivada, o índice PARCIAL libera
      end
      active = in_workspace(ws) { Person.where(archived_at: nil).where("lower(btrim(name)) = 'ana'").count }
      expect(active).to eq(1)
    end

    it 'nome só com espaços é recusado pelo CHECK' do
      in_workspace(ws) do
        expect { conn.execute("INSERT INTO people (id, workspace_id, name) VALUES (#{q(SecureRandom.uuid)}, #{q(ws.id)}, '   ')") }
          .to raise_error(ActiveRecord::StatementInvalid, /chk_people_name_not_blank|violates check/)
      end
    end
  end

  describe 'trigger de arquivamento (D-PERSON-DEL)' do
    it 'arquivar uma Person SEM membership passa' do
      pid = in_workspace(ws) { Person.create!(name: 'Bruno').id }
      expect { in_workspace(ws) { conn.execute("UPDATE people SET archived_at = now() WHERE id = #{q(pid)}") } }
        .not_to raise_error
    end

    it 'arquivar uma Person COM membership ativa é barrado pelo banco (não só pela policy)' do
      bruno = create(:user, name: 'Bruno Membro')
      add_member(ws, bruno, 'edit') # cria Person + Membership
      pid = in_workspace(ws) { Person.find_by(user_id: bruno.id).id }

      expect do
        in_workspace(ws) { conn.execute("UPDATE people SET archived_at = now() WHERE id = #{q(pid)}") }
      end.to raise_error(ActiveRecord::StatementInvalid, /membership ativa/)
      # a pessoa continua ativa
      expect(in_workspace(ws) { Person.find(pid).archived_at }).to be_nil
    end
  end

  describe 'workspace_backups — RLS e isolamento (D2)' do
    def insert_backup(workspace_id:, status: 'pending')
      conn.execute("INSERT INTO workspace_backups (id, workspace_id, status, counts) " \
                   "VALUES (#{q(SecureRandom.uuid)}, #{q(workspace_id)}, #{q(status)}, '{}'::jsonb)")
    end

    it 'a sessão do workspace A vê só os próprios backups' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      in_workspace(ws)    { insert_backup(workspace_id: ws.id) }
      in_workspace(other) { 2.times { insert_backup(workspace_id: other.id) } }
      expect(in_workspace(ws) { WorkspaceBackup.count }).to eq(1)
      expect(in_workspace(other) { WorkspaceBackup.count }).to eq(2)
    end

    it 'INSERT com workspace_id de outro tenant falha no WITH CHECK' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      expect { in_workspace(ws) { insert_backup(workspace_id: other.id) } }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security|violates/)
    end

    it 'status inválido é recusado pelo CHECK' do
      expect { in_workspace(ws) { insert_backup(workspace_id: ws.id, status: 'bogus') } }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_wb_status|violates check/)
    end
  end
end
