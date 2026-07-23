# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('config/env_schema')

# delivery-and-observability 1.1/1.4 — o registro único e o guarda de boot.
RSpec.describe EnvSchema do
  describe '.render_dotenv × backend/.env.example' do
    it 'o arquivo versionado está em sincronia com o schema' do
      committed = File.read(Rails.root.join('.env.example'))
      expect(committed).to eq(described_class.render_dotenv),
                           'backend/.env.example divergiu do schema — rode `bundle exec rake env:example` e commite'
    end

    it 'não lista nenhuma chave de Asaas/WhatsApp' do
      expect(described_class.render_dotenv).not_to match(/ASAAS|WHATSAPP|EVOLUTION/i)
    end
  end

  describe '.missing (guarda de boot)' do
    it 'nomeia TODAS as obrigatórias ausentes de uma vez em production' do
      keys = %w[DATABASE_URL SECRET_KEY_BASE REDIS_URL ACTION_CABLE_URL CORS_ORIGINS]
      saved = keys.to_h { |k| [k, ENV[k]] }
      keys.each { |k| ENV.delete(k) }
      begin
        names = described_class.missing(:production).map(&:name)
        expect(names).to include(*keys)
      ensure
        saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end

    it 'não exige as opcionais (têm default seguro)' do
      names = described_class.missing(:production).map(&:name)
      expect(names).not_to include('FORCE_SSL', 'COOKIES_SAME_SITE', 'RAILS_MAX_THREADS')
    end

    it 'em development não há obrigatórias (defaults do schema valem)' do
      expect(described_class.missing(:development)).to be_empty
    end
  end

  describe '.fetch' do
    it 'devolve o default do schema quando o ENV está vazio' do
      saved = ENV['COOKIES_SAME_SITE']
      ENV.delete('COOKIES_SAME_SITE')
      begin
        expect(described_class.fetch('COOKIES_SAME_SITE')).to eq('lax')
      ensure
        ENV['COOKIES_SAME_SITE'] = saved unless saved.nil?
      end
    end

    it 'levanta em variável não registrada' do
      expect { described_class.fetch('NAO_EXISTE') }.to raise_error(ArgumentError)
    end
  end
end
