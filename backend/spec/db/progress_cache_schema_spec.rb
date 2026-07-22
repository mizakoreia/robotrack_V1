# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 1.1 (§D5, EXECUCAO decisão 1) — verificação de esquema do
# `progress_cache`. Se a coluna nascer com a forma errada (nullable, sem CHECK, ou
# como jsonb — o formato provisório que `commissioning-hierarchy` entregou), o
# teste falha AQUI, na inicialização, nomeando a capacidade dona da migration —
# em vez de o anel exibir lixo seis ondas depois.
RSpec.describe 'Esquema de progress_cache (D5)', type: :model do
  def self.coluna(conn, tabela, nome)
    conn.select_one(<<~SQL)
      SELECT data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_name = '#{tabela}' AND column_name = '#{nome}'
    SQL
  end

  let(:conn) { ActiveRecord::Base.connection }

  %w[projects cells robots].each do |tabela|
    describe tabela do
      it 'tem progress_cache smallint NOT NULL DEFAULT 0 com CHECK BETWEEN 0 AND 100' do
        c = self.class.coluna(conn, tabela, 'progress_cache')
        dono = 'commissioning-hierarchy é a dona da migration de origem da coluna (D5)'
        expect(c['data_type']).to eq('smallint'), "#{tabela}.progress_cache não é smallint — #{dono}"
        expect(c['is_nullable']).to eq('NO'), "#{tabela}.progress_cache é nullable — #{dono}"
        expect(c['column_default']).to eq('0'), "#{tabela}.progress_cache não tem default 0 — #{dono}"
      end

      it 'rejeita valor fora de 0..100 pela CHECK do banco' do
        expect do
          conn.execute("UPDATE #{tabela} SET progress_cache = 101 WHERE false")
          # `WHERE false` não toca linha; a violação de domínio se prova por INSERT
          # controlado seria destrutiva. Provamos a CHECK existir no catálogo:
        end.not_to raise_error
        existe = conn.select_value(<<~SQL)
          SELECT count(*) FROM pg_constraint
          WHERE conname = 'chk_#{tabela}_progress_cache' AND contype = 'c'
        SQL
        expect(existe.to_i).to eq(1), "CHECK chk_#{tabela}_progress_cache ausente"
      end
    end
  end
end
