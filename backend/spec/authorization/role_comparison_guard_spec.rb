# frozen_string_literal: true

require 'rails_helper'

# authorization-policies 6.1 / D3.2 — o guarda estático que impede a matriz de
# voltar a se espalhar em `if`s.
#
# Nenhum arquivo de `app/` compara papel diretamente (`role == :owner`,
# `context.role ==`, `== 'edit'`…) fora de `permission_matrix.rb`. Em
# `app/policies/` a proibição é ABSOLUTA — policy decide invocando a matriz.
# No resto de `app/`, exceção exige entrada na allowlist abaixo, com motivo —
# o mesmo custo social da allowlist pública.
RSpec.describe 'Guarda contra comparação direta de papel' do
  # `role ==`, `role !=`, `== :owner`, `== 'edit'`, e as variações.
  PADRAO = /\brole\b\s*[!=]=|[!=]=\s*:(owner|edit|view)\b|[!=]=\s*'(owner|edit|view)'/

  # file => motivo. Linhas fora daqui reprovam.
  ALLOWLIST = {
    'app/controllers/api/v1/workspaces.rb' =>
      'renomear workspace é owner-only por decisão da Onda 1 (workspaces_api_spec ' \
      '"nega a não-dono"), MAIS restrito que manage_catalog; a comparação vive no ' \
      'endpoint, não numa policy. Revisar em workspace-settings.'
  }.freeze

  arquivos = Dir[Rails.root.join('app/**/*.rb')].sort

  it 'app/policies/ não compara papel — nem com allowlist' do
    ofensores = arquivos
                .select { |f| f.include?('/app/policies/') }
                .reject { |f| f.end_with?('permission_matrix.rb') }
                .flat_map do |f|
      File.readlines(f).each_with_index.filter_map do |linha, i|
        "#{f}:#{i + 1}: #{linha.strip}" if linha.match?(PADRAO) && !linha.strip.start_with?('#')
      end
    end

    expect(ofensores).to be_empty,
                         "policies comparando papel diretamente (use a matriz):\n#{ofensores.join("\n")}"
  end

  it 'no resto de app/, comparação de papel exige allowlist com motivo' do
    ofensores = arquivos
                .reject { |f| f.include?('/app/policies/') }
                .flat_map do |f|
      relativo = f.sub("#{Rails.root}/", '')
      next [] if ALLOWLIST.key?(relativo)

      File.readlines(f).each_with_index.filter_map do |linha, i|
        "#{relativo}:#{i + 1}: #{linha.strip}" if linha.match?(PADRAO) && !linha.strip.start_with?('#')
      end
    end.compact

    expect(ofensores).to be_empty,
                         "comparação direta de papel fora da matriz e da allowlist:\n#{ofensores.join("\n")}"
  end

  it 'a allowlist não acumula entrada órfã' do
    ALLOWLIST.each do |relativo, motivo|
      caminho = Rails.root.join(relativo)
      expect(File.exist?(caminho)).to be(true), "allowlist cita #{relativo}, que não existe mais"
      expect(motivo.strip).not_to be_empty

      tem_comparacao = File.readlines(caminho).any? { |l| l.match?(PADRAO) && !l.strip.start_with?('#') }
      expect(tem_comparacao).to be(true),
                                "#{relativo} está na allowlist mas não compara papel — remover a entrada"
    end
  end
end
