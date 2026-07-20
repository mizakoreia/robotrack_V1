# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::MagicLoginService do
  let!(:user_type) { UserType.create!(name: 'client', description: 'Cliente', hierarchy_level: 10) }
  let!(:user) { User.create!(name: 'Cliente', phone: '5511999999999', user_type: user_type, provider: 'whatsapp') }

  before do
    allow(EvolutionConnection).to receive(:instance_name).and_return('TEST')
    allow(EvolutionConnection).to receive(:send_message).and_return({ status: 'success', response: { 'id' => 'MSG1' } })
  end

  it 'envia código via WhatsApp com sucesso' do
    service = described_class.new(identifier: '5511999999999', method: 'whatsapp', ip_address: '127.0.0.1',
                                  user_agent: 'RSpec')
    result = service.execute!
    expect(result[:success]).to eq(true)
    expect(EvolutionConnection).to have_received(:send_message)
  end

  it 'retorna erro para número inválido' do
    service = described_class.new(identifier: '123', method: 'whatsapp', ip_address: '127.0.0.1', user_agent: 'RSpec')
    result = service.execute!
    expect(result[:success]).to eq(false)
    expect(result[:status]).to eq(422)
  end

  it 'expira código em 5 minutos' do
    service = described_class.new(identifier: '5511999999999', method: 'whatsapp', ip_address: '127.0.0.1',
                                  user_agent: 'RSpec')
    result = service.execute!
    expect(result[:success]).to eq(true)
    code = LoginCode.by_destination('5511999999999').by_method('whatsapp').recent.first
    expect(code.expires_at).to be_within(10.seconds).of(5.minutes.from_now)
  end

  it 'envia código via email com sucesso' do
    User.create!(name: 'Cliente Email', email: 'cliente@example.com', user_type: user_type,
                 provider: 'email')
    service = described_class.new(identifier: 'cliente@example.com', method: 'email', ip_address: '127.0.0.1',
                                  user_agent: 'RSpec')
    result = service.execute!
    expect(result[:success]).to eq(true)
  end
end
