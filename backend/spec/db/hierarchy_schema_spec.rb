# frozen_string_literal: true

require 'rails_helper'

# commissioning-hierarchy 1.6 — o contrato de esquema de D1/D13/D-H3/D-H5/D-H7
# lido do CATÁLOGO do Postgres, não do model. É o que impede a próxima
# capacidade de criar uma tabela `bigserial` por hábito do template, ou de
# esquecer o DEFERRABLE que a renumeração em lote exige.
RSpec.describe 'Esquema da hierarquia de comissionamento' do
  conn = ActiveRecord::Base.connection

  HIERARQUIA = {
    'projects' => { escopo: 'workspace_id' },
    'cells'    => { escopo: 'project_id' },
    'robots'   => { escopo: 'cell_id' }
  }.freeze

  # Allowlist de NÃO-domínio (mesma da guarda de tenancy da Onda 1).
  NAO_DOMINIO = %w[
    users user_types jwt_denylist schema_migrations ar_internal_metadata
    action_text_rich_texts active_storage_attachments
    active_storage_blobs active_storage_variant_records
  ].freeze

  def self.coluna(conn, tabela, nome)
    conn.select_one(
      'SELECT data_type, is_nullable, column_default FROM information_schema.columns ' \
      "WHERE table_name = #{conn.quote(tabela)} AND column_name = #{conn.quote(nome)}"
    )
  end

  it 'TODA tabela de domínio tem PK id uuid (D1/D13) — bigserial reprova aqui' do
    tabelas = conn.select_values("SELECT tablename FROM pg_tables WHERE schemaname = 'public'") - NAO_DOMINIO
    tabelas.sort.each do |tabela|
      id = self.class.coluna(conn, tabela, 'id')
      expect(id).not_to be_nil, "#{tabela} sem coluna id"
      expect(id['data_type']).to eq('uuid'), "#{tabela}.id é #{id['data_type']} — o contrato D13 exige uuid"
    end
  end

  HIERARQUIA.each do |tabela, meta|
    describe tabela do
      it 'tem id uuid com default gen_random_uuid() e workspace_id NOT NULL' do
        id = self.class.coluna(conn, tabela, 'id')
        expect(id['data_type']).to eq('uuid')
        expect(id['column_default']).to include('gen_random_uuid')

        ws = self.class.coluna(conn, tabela, 'workspace_id')
        expect(ws['is_nullable']).to eq('NO')
      end

      it 'tem RLS FORÇADA e a policy tenant_isolation' do
        forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = #{conn.quote(tabela)}")
        expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true), "#{tabela} sem FORCE RLS"

        policies = conn.select_value(
          "SELECT count(*) FROM pg_policies WHERE tablename = #{conn.quote(tabela)} AND policyname = 'tenant_isolation'"
        ).to_i
        expect(policies).to eq(1)
      end

      it 'tem progress_cache jsonb NOT NULL default {} e progress_cached_at (D5/D-H7)' do
        cache = self.class.coluna(conn, tabela, 'progress_cache')
        expect(cache['data_type']).to eq('jsonb')
        expect(cache['is_nullable']).to eq('NO')
        expect(cache['column_default']).to include("'{}'")
        expect(self.class.coluna(conn, tabela, 'progress_cached_at')).not_to be_nil
      end

      it 'tem lock_version e updated_by_person_id com ON DELETE SET NULL (D-H9/D-H6)' do
        expect(self.class.coluna(conn, tabela, 'lock_version')['is_nullable']).to eq('NO')

        del = conn.select_value(<<~SQL)
          SELECT confdeltype FROM pg_constraint
          WHERE conrelid = '#{tabela}'::regclass AND contype = 'f'
            AND pg_get_constraintdef(oid) LIKE '%updated_by_person_id%'
        SQL
        expect(del).to eq('n'), "#{tabela}.updated_by_person_id deveria ser ON DELETE SET NULL"
      end

      it "unicidade de posição por #{meta[:escopo]} é DEFERRABLE (D-H3)" do
        row = conn.select_one(<<~SQL)
          SELECT condeferrable, pg_get_constraintdef(oid) AS def FROM pg_constraint
          WHERE conrelid = '#{tabela}'::regclass AND contype = 'u'
            AND pg_get_constraintdef(oid) LIKE '%position%'
        SQL
        expect(row).not_to be_nil, "#{tabela} sem UNIQUE de position"
        expect(row['def']).to include("#{meta[:escopo]}, \"position\"").or include("#{meta[:escopo]}, position")
        expect(ActiveModel::Type::Boolean.new.cast(row['condeferrable'])).to be(true),
                                                                             "#{tabela}: UNIQUE de position precisa ser DEFERRABLE para a renumeração em lote"
      end

      it "nome é único por #{meta[:escopo]} case-insensitive e o CHECK barra nome vazio (D-H8)" do
        indice = conn.select_value(
          "SELECT indexdef FROM pg_indexes WHERE tablename = #{conn.quote(tabela)} AND indexdef LIKE '%lower(%name%'"
        )
        expect(indice).not_to be_nil, "#{tabela} sem índice único de lower(name)"
        expect(indice).to include('UNIQUE').and include(meta[:escopo])

        check = conn.select_value(<<~SQL)
          SELECT count(*) FROM pg_constraint
          WHERE conrelid = '#{tabela}'::regclass AND contype = 'c'
            AND pg_get_constraintdef(oid) LIKE '%btrim%'
        SQL
        expect(check.to_i).to eq(1), "#{tabela} sem CHECK de nome (1..120, sem só-espaços)"
      end

      it 'tem UNIQUE (id, workspace_id) — o alvo das FKs compostas (D-H5)' do
        count = conn.select_value(<<~SQL)
          SELECT count(*) FROM pg_constraint
          WHERE conrelid = '#{tabela}'::regclass AND contype = 'u'
            AND pg_get_constraintdef(oid) LIKE '%id, workspace_id%'
        SQL
        expect(count.to_i).to eq(1)
      end
    end
  end

  it 'cells → projects e robots → cells têm FK COMPOSTA com ON DELETE CASCADE (D-H5/D-H6)' do
    { 'cells' => 'projects', 'robots' => 'cells' }.each do |filho, pai|
      fk = conn.select_one(<<~SQL)
        SELECT confdeltype, pg_get_constraintdef(oid) AS def FROM pg_constraint
        WHERE conrelid = '#{filho}'::regclass AND contype = 'f'
          AND confrelid = '#{pai}'::regclass
      SQL
      expect(fk).not_to be_nil, "#{filho} sem FK para #{pai}"
      expect(fk['def']).to include('workspace_id'), "FK #{filho}→#{pai} não é composta com workspace_id"
      expect(fk['confdeltype']).to eq('c'), "FK #{filho}→#{pai} não cascateia (é '#{fk['confdeltype']}')"
    end
  end

  it 'robots.application tem CHECK dos seis literais da §1.2 (D-H10)' do
    check = conn.select_value(<<~SQL)
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid = 'robots'::regclass AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%application%'
    SQL
    expect(check).not_to be_nil
    ['Misto / Geral', 'Solda Ponto', 'Solda MIG', 'Handling', 'Sealing', 'Outros'].each do |valor|
      expect(check).to include(valor)
    end
  end

  it 'RLS fail-closed: sem contexto, as três tabelas devolvem zero linhas' do
    HIERARQUIA.each_key do |tabela|
      count = conn.select_value("SELECT count(*) FROM #{tabela}")
      expect(count.to_i).to eq(0), "#{tabela} visível sem app.current_workspace_id"
    end
  end
end
