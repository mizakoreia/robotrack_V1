# frozen_string_literal: true

require 'rails_helper'

# tenant-isolation §"Isolamento entre tenants" e §"Fail-closed" (tarefas 3.4-3.6).
#
# `people` faz o papel de "tabela de domínio" — as capacidades a jusante
# (projetos, células, tarefas) herdam exatamente o mesmo padrão de RLS. O ponto
# de cada cenário é: o isolamento está no BANCO, não no Ruby. Um `unscoped`, um
# SQL cru ou um `delete_all` não contornam a política.
RSpec.describe 'Isolamento entre tenants', :tenancy do
  let(:ws_a) { make_workspace(name: 'WS-A') }
  let(:ws_b) { make_workspace(name: 'WS-B') }

  # ---- 3.4 leitura -----------------------------------------------------------
  describe 'leitura (3.4)' do
    let!(:ids_a) { seed_people(ws_a, 12) }
    let!(:ids_b) { seed_people(ws_b, 30) }

    it 'find por id de outro tenant levanta RecordNotFound' do
      in_workspace(ws_a) do
        expect { Person.find(ids_b.first) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it 'unscoped.count não contorna a política (12, não 42)' do
      in_workspace(ws_a) do
        expect(Person.unscoped.count).to eq(12)
      end
    end

    it 'SQL cru só enxerga as linhas do tenant corrente' do
      in_workspace(ws_a) do
        rows = ActiveRecord::Base.connection.select_all('SELECT id FROM people')
        expect(rows.count).to eq(12)
      end
    end
  end

  # ---- 3.5 escrita -----------------------------------------------------------
  describe 'escrita (3.5)' do
    let!(:ids_a) { seed_people(ws_a, 12) }
    let!(:ids_b) { seed_people(ws_b, 30) }

    it 'INSERT marcado com workspace_id alheio é rejeitado pelo WITH CHECK' do
      in_workspace(ws_a) do
        expect { Person.create!(workspace_id: ws_b.id, name: 'Intruso') }
          .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end
    end

    it 'UPDATE não consegue mover linha para outro tenant' do
      in_workspace(ws_a) do
        conn = ActiveRecord::Base.connection
        expect do
          conn.execute("UPDATE people SET workspace_id = #{conn.quote(ws_b.id)} WHERE id = #{conn.quote(ids_a.first)}")
        end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end
      # As 30 linhas de WS-B seguem intactas.
      in_workspace(ws_b) { expect(Person.unscoped.count).to eq(30) }
    end

    it 'delete_all não alcança outro tenant' do
      in_workspace(ws_a) { Person.delete_all }
      in_workspace(ws_a) { expect(Person.unscoped.count).to eq(0) }
      in_workspace(ws_b) { expect(Person.unscoped.count).to eq(30) }
    end
  end

  # ---- 3.6 fail-closed -------------------------------------------------------
  describe 'fail-closed sem contexto (3.6)' do
    before do
      seed_people(ws_a, 18)
      seed_people(ws_b, 22) # 40 pessoas no total, em dois workspaces
    end

    it 'leitura sem Tenant.with retorna 0' do
      expect(Person.count).to eq(0)
      expect(Person.unscoped.count).to eq(0)
    end

    it 'escrita sem Tenant.with é rejeitada pela política' do
      expect { Person.create!(workspace_id: ws_a.id, name: 'Sem contexto') }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end
end
