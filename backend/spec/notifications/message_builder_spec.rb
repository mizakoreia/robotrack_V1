# frozen_string_literal: true

require 'rails_helper'

# in-app-notifications 2.2/2.3 — contrato das mensagens versionadas.
RSpec.describe Notifications::MessageBuilder do
  let(:base) { { author: 'Bruno', task: 'Ajuste de TCP', robot: 'R03 - Handling' } }

  describe 'contrato caractere-a-caractere (§2.7)' do
    it 'assign' do
      msg = described_class.build(type: 'assign', **base)[:msg]
      expect(msg).to eq('Bruno atribuiu você à tarefa "Ajuste de TCP" (robô R03 - Handling)')
    end

    it 'progress (o %% rende % sem espaço antes)' do
      msg = described_class.build(type: 'progress', n: 45, comment: 'Calibrado eixo 6', **base)[:msg]
      expect(msg).to eq('Bruno registrou 45% na tarefa "Ajuste de TCP" (robô R03 - Handling): Calibrado eixo 6')
    end

    it 'done' do
      msg = described_class.build(type: 'done', **base)[:msg]
      expect(msg).to eq('Tarefa "Ajuste de TCP" (robô R03 - Handling) foi concluída por Bruno')
    end
  end

  it 'grava o format_version usado' do
    expect(described_class.build(type: 'done', **base)[:format_version]).to eq(1)
  end

  describe 'truncagem (2.2 + inv. 8)' do
    it 'comentário de 900 chars → msg de EXATAMENTE 500, com task e robô íntegros' do
      result = described_class.build(type: 'progress', n: 45, comment: 'x' * 900, **base)
      expect(result[:msg].length).to eq(500)
      expect(result[:msg]).to include('Ajuste de TCP')
      expect(result[:msg]).to include('R03 - Handling') # nome do robô nunca cortado
      expect(result[:msg]).to end_with('…')
    end

    it 'comentário curto não é truncado' do
      msg = described_class.build(type: 'progress', n: 10, comment: 'curto', **base)[:msg]
      expect(msg).to end_with(': curto')
    end
  end

  describe 'grep-guard (2.3 / D14)' do
    it 'a string de assign não aparece fora de config/locales e de specs' do
      root = Rails.root
      offenders = Dir.glob(root.join('{app,lib,config}/**/*.rb')).select do |f|
        File.read(f).include?('atribuiu você à tarefa')
      end
      expect(offenders).to be_empty, "string de notificação fora do locale: #{offenders.join(', ')}"
    end
  end
end
