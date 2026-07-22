# frozen_string_literal: true

# hierarchy-screens 1.3 (D-A / D15) — o scanner recursivo que caça a chave
# `progress` em qualquer profundidade de uma resposta. É o guarda contra o alias
# "por conveniência do front": um único campo `progress` reintroduz a ambiguidade
# que D-A existe para eliminar (anel = ponderado, hub = crua). Usado no contrato
# das entities (G1) e reusado no contrato de request de cada endpoint (G2/G3).
#
# Procura a chave EXATA `progress` (string ou símbolo). `weighted_progress` e
# `raw_completion` são permitidos — a proibição é o `progress` genérico e solto.
module ProgressKeyScanner
  module_function

  # Devolve os caminhos (ex.: "projects[0].progress") onde a chave proibida aparece.
  def offending_paths(node, path = 'root')
    case node
    when Hash
      node.flat_map do |k, v|
        here = k.to_s == 'progress' ? ["#{path}.#{k}"] : []
        here + offending_paths(v, "#{path}.#{k}")
      end
    when Array
      node.each_with_index.flat_map { |v, i| offending_paths(v, "#{path}[#{i}]") }
    else
      []
    end
  end

  def contains_progress_key?(node)
    !offending_paths(node).empty?
  end
end
