# frozen_string_literal: true

# Testes do service Auth::CheckoutSessionService
# Verifica criação/retomada de sessão após checkout, tokens e políticas de atualização de usuário
require 'rails_helper'

RSpec.describe Auth::CheckoutSessionService, type: :service do
  let!(:client_type) { UserType.create!(name: 'client', hierarchy_level: 10) }
  let!(:plan) { Plan.create!(title: 'Pro', price: 100.0, billing_kind: 'one_time', allows_console_access: true) }

  def build_purchase(attrs = {})
    Purchase.create!({
      plan: plan,
      consumer_name: 'Teste',
      consumer_email: 'teste@example.com',
      consumer_cpf_cnpj: '12345678901',
      consumer_whatsapp: '5599999999999',
      plan_name: plan.title,
      customer_id: 'cus_123',
      billing_type: 'PIX',
      cycle: 'UNIQUE',
      value: 100.0,
      status: 'DONE',
      payment_id: 'PAY_ABC123'
    }.merge(attrs))
  end

  it 'retorna requires_login para conta já existente' do
    user = User.create!(name: 'Teste', email: 'teste@example.com', user_type: client_type)
    purchase = build_purchase(consumer_email: user.email)
    service = described_class.new
    res = service.execute!(payment_id: purchase.payment_id)
    expect(res[:status]).to eq(200)
    expect(res[:data][:requires_login]).to be_truthy
  end

  it 'gera tokens para conta criada no checkout' do
    purchase = build_purchase(consumer_email: 'novo@example.com')
    service = described_class.new
    res = service.execute!(payment_id: purchase.payment_id)
    expect(res[:status]).to eq(200)
    data = res[:data]
    expect(data[:access_token] || data[:token]).to be_present
    expect(data[:refresh_token]).to be_present
    expect(data[:user]).to be_present
  end

  it 'falha quando compra não está DONE' do
    purchase = build_purchase(status: 'PENDING')
    service = described_class.new
    res = service.execute!(payment_id: purchase.payment_id)
    expect(res[:status]).to eq(422)
  end
end

