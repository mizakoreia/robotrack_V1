# frozen_string_literal: true

module Hierarchy
  # commissioning-hierarchy 3.2 (D-H2): criação idempotente com id do cliente.
  #
  # O INSERT roda num SAVEPOINT (`requires_new`) — uma violação de unicidade
  # envenenaria a transação de request do middleware. Na colisão, a decisão:
  #
  #   id existe no MEU workspace, com os mesmos atributos-chave → :replay (200)
  #   id existe no MEU workspace, atributos divergem            → :conflict (409 + recurso atual)
  #   id existe em OUTRO workspace                              → :not_found (404)
  #   colisão foi de NOME (id novo, nome duplicado no escopo)   → :name_taken (409)
  #
  # O :not_found não é checagem de aplicação: a RLS esconde a linha alheia, o
  # `find_by(id:)` volta nil e é ISSO que o distingue — a PK nunca vira oráculo
  # de enumeração entre tenants (o corpo do 404 é o mesmo de id inexistente).
  class IdempotentCreate
    Result = Struct.new(:outcome, :record, keyword_init: true)

    # match_keys: atributos que definem "o mesmo POST" (nome + pai).
    def self.call(model:, attributes:, match_keys:)
      record = model.transaction(requires_new: true) { model.create!(attributes) }
      Result.new(outcome: :created, record: record)
    rescue ActiveRecord::RecordNotUnique => e
      # A violação pode ser da PK (idempotência) OU do índice de nome único do
      # escopo (D-H8) — o nome do índice na mensagem do Postgres distingue.
      return Result.new(outcome: :name_taken, record: nil) if e.message.include?('lower_name')

      existing = attributes[:id] ? model.find_by(id: attributes[:id]) : nil
      return Result.new(outcome: :not_found, record: nil) if existing.nil?

      replay = match_keys.all? { |key| existing.public_send(key) == attributes[key] }
      Result.new(outcome: replay ? :replay : :conflict, record: existing)
    end
  end
end
