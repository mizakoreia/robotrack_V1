# frozen_string_literal: true

require 'rails_helper'

# tenant-isolation §"workspace_id NOT NULL" e §"RLS habilitada e forçada"
# (tarefa 4.6). Esta guarda é o que faz D2 valer para as ~20 capacidades a
# jusante que nunca vão ler o design.md: uma tabela de domínio criada sem
# `workspace_id NOT NULL`, sem `FORCE ROW LEVEL SECURITY` ou sem a policy
# `tenant_isolation` reprova o CI, nomeando a tabela.
RSpec.describe 'Guarda de esquema de tenancy' do
  conn = ActiveRecord::Base.connection

  # Allowlist explícita de NÃO-tenant (sem workspace_id, sem RLS): auth, metadados
  # do Rails e tabelas do template ActionText/ActiveStorage.
  NON_TENANT_TABLES = %w[
    users user_types jwt_denylist schema_migrations ar_internal_metadata
    action_text_rich_texts active_storage_attachments
    active_storage_blobs active_storage_variant_records
  ].freeze

  # Tabelas de CONTROLE: têm RLS forçada mas NÃO têm coluna workspace_id — o
  # workspace é a própria linha (ou é resolvido por user_id).
  CONTROL_TABLES = %w[workspaces].freeze

  all_tables = conn.select_values(
    "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
  ).sort
  domain_tables = all_tables - NON_TENANT_TABLES - CONTROL_TABLES

  def forced_rls?(table)
    c = ActiveRecord::Base.connection
    ActiveModel::Type::Boolean.new.cast(
      c.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = #{c.quote(table)}")
    )
  end

  def tenant_policy?(table)
    c = ActiveRecord::Base.connection
    c.select_value(
      "SELECT count(*) FROM pg_policies WHERE tablename = #{c.quote(table)} " \
      "AND policyname = 'tenant_isolation'"
    ).to_i == 1
  end

  it 'há tabelas de domínio para verificar (people, memberships)' do
    expect(domain_tables).not_to be_empty
  end

  domain_tables.each do |table|
    describe "tabela de domínio #{table}" do
      it 'tem workspace_id NOT NULL' do
        nullable = conn.select_value(
          "SELECT is_nullable FROM information_schema.columns " \
          "WHERE table_name = #{conn.quote(table)} AND column_name = 'workspace_id'"
        )
        expect(nullable).not_to be_nil,
                                "#{table} não tem coluna workspace_id — a allowlist NON_TENANT_TABLES " \
                                'é o único caminho de exceção'
        expect(nullable).to eq('NO'), "#{table}.workspace_id permite NULL — vira dado órfão invisível"
      end

      it 'tem índice cujo primeiro atributo é workspace_id' do
        count = conn.select_value(<<~SQL).to_i
          SELECT count(*)
          FROM pg_index i
          JOIN pg_class c ON c.oid = i.indrelid
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = i.indkey[0]
          WHERE c.relname = #{conn.quote(table)} AND a.attname = 'workspace_id'
        SQL
        expect(count).to be > 0, "#{table} não tem índice começando por workspace_id (custo de RLS)"
      end

      it 'tem FORCE ROW LEVEL SECURITY e policy tenant_isolation' do
        expect(forced_rls?(table)).to be(true), "#{table} não tem FORCE RLS"
        expect(tenant_policy?(table)).to be(true), "#{table} não tem policy tenant_isolation"
      end
    end
  end

  CONTROL_TABLES.each do |table|
    it "#{table} (controle) tem FORCE RLS e policy tenant_isolation" do
      expect(forced_rls?(table)).to be(true)
      expect(tenant_policy?(table)).to be(true)
    end
  end
end
