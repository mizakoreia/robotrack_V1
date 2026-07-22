# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 6.1 (D14/D15) — os rótulos das métricas são strings pt-BR
# centralizadas e versionadas. Uma chave ausente falha em TESTE (não renderiza a
# chave crua ao usuário), e um literal de rótulo espalhado no código falha o lint.
RSpec.describe 'Rótulos de métrica de progresso (D14)', type: :model do
  it 'as duas chaves de rótulo existem no locale pt-BR (completude)' do
    expect(I18n.t('progress.metrics.weighted.label', locale: :'pt-BR', raise: true)).to eq('Progresso ponderado')
    expect(I18n.t('progress.metrics.raw_count.label', locale: :'pt-BR', raise: true))
      .to eq('Progresso físico (tarefas concluídas)')
  end

  it 'remover uma chave de rótulo falha aqui, não em runtime' do
    expect { I18n.t('progress.metrics.inexistente.label', locale: :'pt-BR', raise: true) }
      .to raise_error(I18n::MissingTranslationData)
  end

  it 'nenhum literal de rótulo vive no código Ruby (só no locale)' do
    literais = ['Progresso ponderado', 'Progresso físico (tarefas concluídas)']
    ofensores = []
    Dir[Rails.root.join('app/**/*.rb')].each do |file|
      conteudo = File.read(file)
      literais.each { |lit| ofensores << "#{file.sub(Rails.root.to_s, '')}: #{lit}" if conteudo.include?(lit) }
    end
    expect(ofensores).to be_empty,
                         "rótulo literal fora do locale (use I18n.t('progress.metrics.*.label')):\n#{ofensores.join("\n")}"
  end
end
