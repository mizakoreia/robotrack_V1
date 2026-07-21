# frozen_string_literal: true

require 'rails_helper'

# authorization-policies 5.2 — o meta-spec que impede uma invariante de sumir.
#
# `spec/authorization/invariants/` tem EXATAMENTE 8 arquivos, um por invariante
# da §4.1, numerados. Excluir um arquivo faz a contagem falhar; marcar `pending`
# sem motivo nomeando a capacidade bloqueadora também falha — pendência sem
# dono é como a invariante caía no vão entre capacidades no WBS anterior.
RSpec.describe 'Completude da suíte de invariantes (§4.1)' do
  DIR = Rails.root.join('spec/authorization/invariants')
  ARQUIVOS = Dir[DIR.join('inv_*_spec.rb')].sort

  it 'existem exatamente 8 arquivos, inv_1 a inv_8' do
    numeros = ARQUIVOS.map { |f| File.basename(f)[/\Ainv_(\d)/, 1].to_i }.sort
    expect(numeros).to eq((1..8).to_a),
                       "esperava inv_1..inv_8, encontrei: #{ARQUIVOS.map { |f| File.basename(f) }}"
  end

  it 'todo pending nomeia a capacidade bloqueadora' do
    ARQUIVOS.each do |arquivo|
      File.readlines(arquivo).each_with_index do |linha, i|
        next unless linha.match?(/^\s*pending[ (]/)

        expect(linha).to match(/bloqueada por [a-z0-9-]+/),
                         "#{File.basename(arquivo)}:#{i + 1} tem pending sem motivo nomeando a " \
                         "capacidade responsável (padrão: pending 'bloqueada por <change>...')"
      end
    end
  end
end
