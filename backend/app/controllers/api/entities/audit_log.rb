# frozen_string_literal: true

module Api
  module Entities
    # audit-log 5.2 (§2.8, Decisão 4/9) — a linha de auditoria como o modal a lê.
    # Expõe SÓ o texto já renderizado e congelado (`msg`, `ts_local`) + `ts`/`by_name`/
    # `event_type`. NÃO expõe `payload` (dado de máquina, interno) nem `by_person_id`
    # (identidade — a autoria pública é o snapshot `by_name`, D6). A leitura usa `msg`/
    # `ts_local` verbatim; o cliente NÃO reformata data (fuso do leitor mentiria).
    class AuditLog < Grape::Entity
      expose(:id)         { |o, _| o.id }
      expose(:msg)        { |o, _| o.msg }
      expose(:ts)         { |o, _| o.ts&.iso8601 }
      expose(:ts_local)   { |o, _| o.ts_local }
      expose(:by_name)    { |o, _| o.by_name }
      expose(:event_type) { |o, _| o.event_type }
    end
  end
end
