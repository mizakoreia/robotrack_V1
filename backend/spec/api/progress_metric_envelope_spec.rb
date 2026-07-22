# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 3.3 (D15) — a varredura das entidades Grape. Nenhum campo
# numérico com `progress`/`percent` no nome pode ser exposto fora dos envelopes
# `weighted_progress` / `raw_completion`. Um `expose :progress` novo numa entidade
# de rollup falha AQUI nomeando entidade, campo e D15 — a convenção de nomes que
# o legado usava (e que deixou os dois números conviverem sem rótulo) não volta.
RSpec.describe 'Envelope de métrica nas entidades (D15)', type: :model do
  ENVELOPES = %w[weighted_progress raw_completion].freeze

  # Isenções com razão: `Api::Entities::Task#progress` é o valor da TAREFA ATÔMICA
  # (governado por progress-advances); `TaskAdvance#from_progress/to_progress` são
  # os extremos do delta de UM avanço na trilha. Nenhum é métrica de rollup
  # (ponderado §2.1 / contagem crua §3.2) — o que o D15 rege.
  ALLOWLIST = {
    'Api::Entities::Task' => %w[progress],
    'Api::Entities::TaskAdvance' => %w[from_progress to_progress]
  }.freeze

  def self.entity_classes
    Api::Entities.constants.map { |c| Api::Entities.const_get(c) }
                 .select { |k| k.is_a?(Class) && k < Grape::Entity }
  end

  it 'nenhuma entidade expõe progress/percent solto fora dos dois envelopes' do
    ofensores = []
    self.class.entity_classes.each do |klass|
      isentos = ALLOWLIST.fetch(klass.name, [])
      klass.root_exposures.map(&:key).map(&:to_s).each do |campo|
        next if ENVELOPES.include?(campo)
        next if isentos.include?(campo)

        ofensores << "#{klass.name}##{campo}" if campo.match?(/progress|percent/i)
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
