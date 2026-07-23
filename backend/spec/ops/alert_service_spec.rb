# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 5.1/5.2/5.4 — canal único, dedup e blindagem.
RSpec.describe Ops::AlertService do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:webhook) { instance_spy(Proc) }
  let(:pager) { instance_spy(Proc) }
  let(:sentry) { instance_spy(Proc) }
  let(:logger) { instance_spy(Logger) }

  subject(:service) do
    described_class.new(cache: cache, webhook: webhook, pager: pager, sentry: sentry, logger: logger)
  end

  def raise_alert(severity: :warning, key: 'k1')
    service.raise_alert(key: key, severity: severity, message: 'm', context: { a: 1 })
  end

  describe 'deduplicação (janela de 1h)' do
    it 'a mesma key notifica UMA vez na janela' do
      expect(raise_alert).to eq(:delivered)
      expect(raise_alert).to eq(:suppressed)
      expect(webhook).to have_received(:call).once
    end

    it 'reemite após a janela de 1h expirar' do
      travel_to(Time.utc(2026, 7, 23, 10, 0, 0)) do
        expect(raise_alert).to eq(:delivered)
        expect(raise_alert).to eq(:suppressed) # 10h30 ainda suprime
      end
      travel_to(Time.utc(2026, 7, 23, 11, 5, 0)) do
        expect(raise_alert).to eq(:delivered) # 11h05 > 1h → reemite
      end
      expect(webhook).to have_received(:call).twice
    end
  end

  describe 'roteamento por severidade' do
    it ':info só loga (nem webhook, nem pager)' do
      expect(raise_alert(severity: :info)).to eq(:delivered)
      expect(webhook).not_to have_received(:call)
      expect(pager).not_to have_received(:call)
    end

    it ':warning → webhook, sem pager' do
      raise_alert(severity: :warning)
      expect(webhook).to have_received(:call)
      expect(pager).not_to have_received(:call)
    end

    it ':critical com PAGER → webhook + pager' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ALERT_PAGER_URL').and_return('https://pager')
      raise_alert(severity: :critical)
      expect(webhook).to have_received(:call)
      expect(pager).to have_received(:call)
    end

    it ':critical SEM pager degrada para log+Sentry, sem levantar (5.4)' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ALERT_PAGER_URL').and_return(nil)
      expect { raise_alert(severity: :critical) }.not_to raise_error
      expect(pager).not_to have_received(:call)
      expect(sentry).to have_received(:call)
    end
  end

  describe 'blindagem contra falha do destino (5.2)' do
    it 'webhook 500 NÃO propaga; a falha vai para o log' do
      allow(webhook).to receive(:call).and_raise(StandardError.new('slack 500'))
      expect { raise_alert(severity: :warning) }.not_to raise_error
      expect(logger).to have_received(:error).with(/alert_delivery_failed/)
    end
  end

  it 'severidade inválida levanta' do
    expect { service.raise_alert(key: 'k', severity: :fatal, message: 'm') }.to raise_error(ArgumentError)
  end
end
