# frozen_string_literal: true

module Robots
  # robot-tasks 5.1 (§2.5, D-RT-4) — normalização da leva NO SERVIDOR (a UI
  # repete por conveniência, não por segurança):
  #
  #   1. `trim` + colapso de espaços internos em cada nome; descarta vazios.
  #   2. dedup por nome normalizado + casefold, preservando a PRIMEIRA ocorrência.
  #   3. clamp em 50 — o excedente é DESCARTADO, não erro.
  #
  # Recebe e devolve pares `{id, name}` (o id é o uuid do cliente, D1). O clamp e
  # a dedup são regra de UX de leva, não de integridade: são do service, não do
  # banco.
  module BatchNormalizer
    MAX = 50

    def self.call(entries)
      seen = {}
      result = []

      Array(entries).each do |entry|
        name = normalize(entry[:name] || entry['name'])
        next if name.empty?

        key = name.downcase
        next if seen[key]

        seen[key] = true
        result << { id: (entry[:id] || entry['id']).presence, name: name }
        break if result.size >= MAX
      end

      result
    end

    def self.normalize(raw)
      raw.to_s.strip.gsub(/\s+/, ' ')
    end
  end
end
