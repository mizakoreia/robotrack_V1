# frozen_string_literal: true

require 'rails_helper'

# notification-preferences G6 (§D-P8) — a migração `ALTER TYPE ... ADD VALUE`
# acrescentou o valor COARSE `'structure'` ao enum `notification_type`, SEM
# remover os originais nem abrir a porta para valores arbitrários.
RSpec.describe 'notification_type enum — valor estrutural (G6)' do
  let(:conn) { ActiveRecord::Base.connection }

  it 'aceita structure' do
    expect(conn.select_value("SELECT 'structure'::public.notification_type")).to eq('structure')
  end

  it 'recusa um valor arbitrário' do
    expect do
      conn.execute("SELECT 'mention'::public.notification_type")
    end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum|notification_type/)
  end

  it 'preserva os três valores originais' do
    %w[assign progress done].each do |v|
      expect(conn.select_value("SELECT '#{v}'::public.notification_type")).to eq(v)
    end
  end
end
