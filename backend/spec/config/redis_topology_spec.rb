# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('config/redis_topology')

# delivery-and-observability 3.2 — o guarda de topologia de Redis.
RSpec.describe RedisTopology do
  let(:prefix) { 'robotrack_production' }

  it 'três URLs distintas (por db) → sem violação' do
    urls = {
      cache: 'redis://r:6379/1',
      queue: 'redis://r:6379/2',
      cable: 'redis://r:6379/3'
    }
    expect(described_class.violations(urls, channel_prefix: prefix)).to be_empty
  end

  it 'cache e fila no mesmo (host, porta, db) → violação nomeando as funções' do
    urls = {
      cache: 'redis://r:6379/1',
      queue: 'redis://r:6379/1',
      cable: 'redis://r:6379/3'
    }
    problems = described_class.violations(urls, channel_prefix: prefix)
    expect(problems.size).to eq(1)
    expect(problems.first).to match(/cache.*queue|queue.*cache/)
  end

  it 'hosts/portas diferentes no mesmo db NÃO colidem' do
    urls = {
      cache: 'redis://a:6379/1',
      queue: 'redis://b:6380/1',
      cable: 'redis://c:6381/1'
    }
    expect(described_class.violations(urls, channel_prefix: prefix)).to be_empty
  end

  it 'channel_prefix ausente → violação' do
    urls = { cache: 'redis://r:6379/1', queue: 'redis://r:6379/2', cable: 'redis://r:6379/3' }
    problems = described_class.violations(urls, channel_prefix: '')
    expect(problems).to include(a_string_matching(/channel_prefix/))
  end
end
