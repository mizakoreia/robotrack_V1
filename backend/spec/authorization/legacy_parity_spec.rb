# frozen_string_literal: true

require 'rails_helper'

# authorization-policies 5.7 / D3.11 — o "linha a linha, não de memória".
#
# `legacy_parity.yml` tem uma entrada por declaração `allow` do
# `firestore.rules` legado (mizakoreia/RoboTrack@50c7a2f — referência externa
# de leitura; o arquivo NÃO é versionado aqui, por decisão do usuário). Este
# spec confere a contagem, exige `covered_by` OU `divergence` por entrada e
# imprime o relatório de divergências — o endurecimento fica visível, não
# some na tradução.
RSpec.describe 'Paridade com firestore.rules (legado)' do
  # 22 declarações `allow` no commit de referência. Se o legado mudar (não
  # deveria — é história), a releitura atualiza o yml E esta constante.
  EXPECTED_ALLOWS = 22

  entradas = YAML.safe_load_file(
    Rails.root.join('config/authorization/legacy_parity.yml')
  )

  it "tem exatamente #{EXPECTED_ALLOWS} entradas — uma por allow do arquivo legado" do
    expect(entradas.size).to eq(EXPECTED_ALLOWS),
                             "#{entradas.size} entradas para #{EXPECTED_ALLOWS} allows — " \
                             'uma rule foi omitida ou duplicada'
  end

  it 'as linhas citadas são únicas e crescentes (espelham o arquivo legado)' do
    linhas = entradas.map { |e| e['line'] }
    expect(linhas).to eq(linhas.sort)
    expect(linhas.uniq.size).to eq(linhas.size)
  end

  entradas.each do |entrada|
    it "L#{entrada['line']} — #{entrada['rule']}: coberta ou divergente, nunca esquecida" do
      coberta   = entrada['covered_by'].to_s.strip
      divergente = entrada['divergence'].to_s.strip

      expect(coberta.empty? && divergente.empty?).to be(false),
                                                     "a entrada da linha #{entrada['line']} não tem covered_by nem divergence — " \
                                                     'rule legada sem rastreabilidade (D3.11)'
    end
  end

  it 'imprime o relatório de divergências (endurecimentos deliberados)' do
    divergencias = entradas.select { |e| e['divergence'].to_s.strip.present? }
    expect(divergencias).not_to be_empty

    relatorio = divergencias.map do |e|
      "  L#{e['line']} #{e['rule']}:\n    #{e['divergence'].strip}"
    end.join("\n")
    puts "\nDivergências deliberadas com firestore.rules (#{divergencias.size}):\n#{relatorio}"

    # D-A e D-B, nomeadas no design, têm de estar entre elas.
    textos = divergencias.map { |e| e['divergence'] }.join(' ')
    expect(textos).to include('D-A')
    expect(textos).to include('D-B')
  end
end
