# frozen_string_literal: true

require 'rails_helper'

# audit-log 3.5 (Decisão 5) — a guarda das format strings versionadas. Compara o
# locale (config/locales/pt-BR.audit.yml) com o SNAPSHOT congelado das versões
# publicadas: editar uma `vN` já publicada, em vez de criar `vN+1`, tem de quebrar o
# build nomeando a chave. Comparação byte a byte da string CRUA do YAML (sem passar
# pelo I18n, que interpolaria).
RSpec.describe 'audit-log — guarda de format string versionada' do
  locale_path   = Rails.root.join('config/locales/pt-BR.audit.yml')
  snapshot_path = Rails.root.join('spec/fixtures/audit/published_format_strings.yml')

  locale   = YAML.load_file(locale_path).dig('pt-BR', 'audit')
  snapshot = YAML.load_file(snapshot_path)

  it 'o locale de auditoria existe e tem a árvore audit.*' do
    expect(locale).to be_a(Hash)
    expect(locale.keys).to include('task_completed', 'workspace_reset')
  end

  snapshot.each do |event, versions|
    versions.each do |version, published_text|
      it "#{event}.#{version} publicada NÃO foi editada (bate byte a byte com o locale)" do
        current = locale.dig(event, version)
        expect(current).not_to be_nil, "#{event}.#{version} sumiu do locale — versão publicada não some"
        expect(current).to eq(published_text),
                           "#{event}.#{version} foi EDITADA após publicada — crie #{event}.v#{version.sub('v', '').to_i + 1}, não edite a #{version}"
      end
    end
  end

  it 'toda versão CORRENTE de AuditLog::FORMAT_VERSIONS existe no locale' do
    AuditLog::FORMAT_VERSIONS.each do |event, version|
      expect(locale.dig(event, "v#{version}")).not_to be_nil,
                                                       "audit.#{event}.v#{version} (corrente) ausente no locale"
    end
  end
end
