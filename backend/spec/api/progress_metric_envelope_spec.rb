# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 3.3 (D15) — a varredura das entidades Grape. Nenhum campo
# numérico com `progress`/`percent` no nome pode ser exposto fora dos envelopes
# `weighted_progress` / `raw_completion`. Um `expose :progress` novo numa entidade
# de rollup falha AQUI nomeando entidade, campo e D15 — a convenção de nomes que
# o legado usava (e que deixou os dois números conviverem sem rótulo) não volta.
RSpec.describe 'Envelope de métrica nas entidades (D15)', type: :model do
  # NOMES ÚNICOS de propósito: um `CONST = ...` dentro de um bloco `RSpec.describe`
  # vaza para o TOPO (Object), então `ENVELOPES`/`ALLOWLIST` colidiriam com os de
  # outros specs (role_comparison_guard usa `ALLOWLIST`) e a última carga venceria,
  # quebrando um ou outro conforme a seed. Prefixamos com `PME_`.
  PME_ENVELOPES = %w[weighted_progress raw_completion].freeze

  # Isenções (string COMPLETA `Entity#campo`) com razão: `Task#progress` é o valor
  # da TAREFA ATÔMICA (progress-advances); `TaskAdvance#from/to_progress` são os
  # extremos do delta de UM avanço. Nenhum é métrica de rollup (§2.1/§3.2).
  PME_EXEMPT = %w[
    Api::Entities::Task#progress
    Api::Entities::TaskAdvance#from_progress
    Api::Entities::TaskAdvance#to_progress
    Api::Entities::MyTaskRow#progress
  ].freeze

  def self.entity_classes
    Api::Entities.constants.map { |c| Api::Entities.const_get(c) }
                 .select { |k| k.is_a?(Class) && k < Grape::Entity }
  end

  it 'nenhuma entidade expõe progress/percent solto fora dos dois envelopes' do
    ofensores = []
    self.class.entity_classes.each do |klass|
      klass.root_exposures.map(&:key).map(&:to_s).each do |campo|
        next unless campo.match?(/progress|percent/i)
        next if PME_ENVELOPES.include?(campo)

        candidato = "#{klass.name}##{campo}"
        ofensores << candidato unless PME_EXEMPT.include?(candidato)
      end
    end
    expect(ofensores).to be_empty,
                         "campos de progresso soltos (D15 — use weighted_progress/raw_completion):\n" \
                         "#{ofensores.join("\n")}"
  end

  it 'o valor de metric fora do enum fechado é rejeitado antes de serializar' do
    expect { ProgressMetric.label('physical') }.to raise_error(ArgumentError, /desconhecida/)
    expect(ProgressMetric.weighted(58)).to include(metric: 'weighted')
    expect(ProgressMetric.raw_completion(completed: 12, total: 40, percent: 30)).to include(metric: 'raw_count')
  end
end
