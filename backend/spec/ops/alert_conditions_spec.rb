# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 5.3/5.4 — condições operacionais e contrato de key.
RSpec.describe Ops::AlertConditions do
  def keys(snapshot)
    described_class.evaluate(snapshot).map { |a| a[:key] }
  end

  it '5xx > 1% em 5 min → critical' do
    expect(keys(error_rate_5m: 0.02)).to include('http_5xx_rate_high')
  end

  it '5xx <= 1% → sem alerta' do
    expect(keys(error_rate_5m: 0.005)).not_to include('http_5xx_rate_high')
  end

  it 'fila sustentada > 1000 por 10 min → warning; drenada não dispara' do
    expect(keys(queue_depth_sustained_10m: 1_200)).to include('sidekiq_queue_backlog')
    expect(keys(queue_depth_sustained_10m: 0)).not_to include('sidekiq_queue_backlog')
  end

  it 'job no dead set → warning' do
    expect(keys(dead_count: 3)).to include('sidekiq_dead_set')
  end

  it 'falha de cable e de release → critical' do
    expect(keys(cable_publish_failed: true)).to include('cable_publish_failure')
    expect(keys(release_failed: true)).to include('release_phase_failure')
  end

  it 'snapshot saudável → nenhum alerta' do
    expect(described_class.evaluate(error_rate_5m: 0.0, queue_depth_sustained_10m: 10, dead_count: 0)).to be_empty
  end
end

RSpec.describe Ops::AlertKeys do
  it 'define os formatos de key consumidos por D5, D7 e convites' do
    expect(described_class.progress_cache_divergence('w1')).to eq('progress_cache_divergence:w1')
    expect(described_class.offline_queue_reconcile_failure('w2')).to eq('offline_queue_reconcile_failure:w2')
    expect(described_class.invitation_delivery_failure('inv1')).to eq('invitation_delivery_failure:inv1')
  end
end
