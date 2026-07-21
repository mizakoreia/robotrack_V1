# frozen_string_literal: true

module Hierarchy
  # commissioning-hierarchy 3.1 (D-H1): validação do id gerado no CLIENTE.
  #
  # Aceita UUID v1–v8 com variante RFC 4122. O UUID nulo é rejeitado com veredito
  # PRÓPRIO — é o que um cliente com bug (ou um parse mal feito) produz, e ele
  # passaria numa checagem de formato frouxa. Ausente é legítimo: o banco gera.
  module IdValidator
    FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    NIL_UUID = '00000000-0000-0000-0000-000000000000'

    # => :absent | :nil_uuid | :malformed | :ok
    def self.verdict(id)
      return :absent if id.nil? || id.to_s.strip.empty?
      return :nil_uuid if id.to_s.downcase == NIL_UUID
      return :malformed unless FORMAT.match?(id.to_s)

      :ok
    end
  end
end
