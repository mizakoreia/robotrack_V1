# frozen_string_literal: true

require 'rails_helper'

# task-catalog 2.4 (§2.5) — a TABELA DE CASOS compartilhada: 6 Aplicações × 4
# formas de filtro, executada contra a versão Ruby E a versão SQL.
#
# Se as duas divergirem em qualquer célula, este spec falha — e essa divergência
# é exatamente o que faria um robô criado em LOTE e o mesmo robô SINCRONIZADO
# terminarem com conjuntos de tarefas diferentes.
#
# Os filtros são gravados por SQL cru de propósito: a normalização de escrita
# (D-TC-2) nunca deixaria `{"Todas"}` ou `{"Misto / Geral"}` persistir pelo
# model, mas o importador legado e um restore de backup deixam.
RSpec.describe TaskTemplates::ApplicabilityFilter, :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ana)  { create(:user) }
  let(:ws)   { make_workspace(owner: ana) }

  # Nomes prefixados: constante declarada dentro de um bloco RSpec cai em
  # Object, e `APLICABILIDADE_ESPERADO`/`APLICABILIDADE_FORMAS` colidiriam com as de matrix_conformance_spec.
  APLICABILIDADE_FORMAS = {
    'vazio' => '{}',
    'curinga Misto / Geral' => '{"Misto / Geral"}',
    'curinga Todas' => '{"Todas"}',
    'específico Sealing' => '{"Sealing"}'
  }.freeze

  # esperado[forma][aplicação]
  APLICABILIDADE_ESPERADO = {
    'vazio' => Hash.new(true),
    'curinga Misto / Geral' => Hash.new(true),
    'curinga Todas' => Hash.new(true),
    'específico Sealing' => Hash.new(false).merge('Sealing' => true)
  }.freeze

  before do
    in_workspace(ws) do
      APLICABILIDADE_FORMAS.each_with_index do |(nome, literal), i|
        conn.execute(<<~SQL)
          INSERT INTO task_templates (workspace_id, cat, "desc", app_filters)
          VALUES (#{conn.quote(ws.id)}, 'X. Teste', #{conn.quote("Forma #{i} — #{nome}")}, '#{literal}')
        SQL
      end
    end
  end

  Robot::APPLICATIONS.each do |aplicacao|
    APLICABILIDADE_FORMAS.each_key do |forma|
      it "#{forma} × #{aplicacao}: Ruby e SQL concordam (#{APLICABILIDADE_ESPERADO[forma][aplicacao]})" do
        esperado = APLICABILIDADE_ESPERADO[forma][aplicacao]

        in_workspace(ws) do
          template = TaskTemplate.find_by!('"desc" LIKE ?', "%#{forma}")

          resultado_ruby = described_class.applicable?(template, aplicacao)
          resultado_sql = described_class.scope_for(aplicacao).exists?(id: template.id)

          expect(resultado_ruby).to eq(esperado),
                                    "versão RUBY divergiu: #{forma} × #{aplicacao} deu #{resultado_ruby}"
          expect(resultado_sql).to eq(esperado),
                                   "versão SQL divergiu: #{forma} × #{aplicacao} deu #{resultado_sql}"
        end
      end
    end
  end

  it 'a versão SQL devolve o conjunto certo de uma vez (Sealing vê 4 de 4; Solda MIG vê 3)' do
    in_workspace(ws) do
      expect(described_class.scope_for('Sealing').count).to eq(4)
      expect(described_class.scope_for('Solda MIG').count).to eq(3)
    end
  end
end
