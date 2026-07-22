# frozen_string_literal: true

module Api
  module Entities
    # commissioning-report 1.1 (§3.8, D-R1) — o CONTRATO do payload. O service já
    # monta o documento inteiro com todos os valores DERIVADOS (carimbo, id,
    # contagens, distribuição, árvore com histórico, conclusões, avisos); a entity
    # só congela a SUPERFÍCIE de topo — o cliente não deriva nada (D-R1). Se um
    # campo derivado sumir aqui, o consumidor teria de calcular; a fixture congelada
    # em `spec/fixtures/reports/commissioning_report.json` guarda isso.
    class CommissioningReport < Grape::Entity
      expose(:scope)                { |o, _| o[:scope] }
      expose(:header)               { |o, _| o[:header] }
      expose(:stamp)                { |o, _| o[:stamp] }
      expose(:document_id)          { |o, _| o[:document_id] }
      expose(:metadata)             { |o, _| o[:metadata] }
      expose(:status_distribution)  { |o, _| o[:status_distribution] }
      expose(:tree)                 { |o, _| o[:tree] }
      expose(:conclusions)          { |o, _| o[:conclusions] }
      expose(:labels)               { |o, _| o[:labels] }
      expose(:warnings)             { |o, _| o[:warnings] }
    end
  end
end
