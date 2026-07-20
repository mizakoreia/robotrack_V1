# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoginCode, type: :model do
  it 'valida expiração em 5 minutos' do
    lc = described_class.create!(destination: '5511999999999', method: 'whatsapp', code: '123456',
                                 expires_at: 5.minutes.from_now)
    expect(lc.expired?).to eq(false)
    expect(lc.time_remaining).to be_between(1, 300)
  end

  it 'marca como expirado após tempo' do
    lc = described_class.create!(destination: '5511999999999', method: 'whatsapp', code: '123456',
                                 expires_at: 1.second.from_now)
    sleep 2
    expect(lc.expired?).to eq(true)
  end
end
