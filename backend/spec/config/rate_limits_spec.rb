# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('config/rate_limits')

# delivery-and-observability 7.2/7.3 — classificação de rota, identidade e limites.
RSpec.describe RateLimits do
  describe '.classify' do
    it 'GET /api → read' do
      expect(described_class.classify('GET', '/api/v1/projects')).to eq(:read)
    end

    it 'POST /api → write' do
      expect(described_class.classify('POST', '/api/v1/projects')).to eq(:write)
    end

    it 'lote de robôs, avanço e relatório têm classe própria' do
      expect(described_class.classify('POST', '/api/v1/robots/batch')).to eq(:robot_batch)
      expect(described_class.classify('POST', '/api/v1/tasks/1/advances')).to eq(:advance)
      expect(described_class.classify('GET', '/api/v1/reports/x')).to eq(:report)
    end

    it 'fora de /api → sem teto de domínio' do
      expect(described_class.classify('POST', '/auth/v1/session')).to be_nil
    end
  end

  describe '.limit' do
    it 'lê o teto do ENV/registro' do
      expect(described_class.limit(:write)).to eq(120)
      expect(described_class.limit(:robot_batch)).to eq(10)
      expect(described_class.limit(:auth)).to eq(5)
    end
  end

  describe '.identity' do
    it 'sem bearer → cai para IP (mesmo NAT não se auto-bloqueia por usuário)' do
      expect(described_class.identity(nil, '10.0.0.1')).to eq('ip:10.0.0.1')
    end

    it 'com JWT válido → user:<sub>, sem tocar o banco' do
      secret = 'test-secret'
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DEVISE_JWT_SECRET_KEY').and_return(secret)
      token = JWT.encode({ 'sub' => 'user-123', 'jti' => 'j1' }, secret, 'HS256')
      expect(described_class.identity(token, '10.0.0.1')).to eq('user:user-123')
    end

    it 'JWT com assinatura inválida → cai para IP' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DEVISE_JWT_SECRET_KEY').and_return('right')
      forged = JWT.encode({ 'sub' => 'x' }, 'wrong', 'HS256')
      expect(described_class.identity(forged, '10.0.0.1')).to eq('ip:10.0.0.1')
    end
  end
end
