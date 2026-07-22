# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 8.2 (D14/D-R9/§5.1) — as duas varreduras do documento:
#
# 1. i18n: toda chave `t(:...)` referenciada pelos serviços do relatório EXISTE em
#    `report.v1.*` — o documento nunca sai com `translation missing`. A varredura
#    lê o FONTE (não uma lista à mão): chave nova usada sem tradução falha aqui.
#
# 2. glifos: nenhuma string do payload carrega caractere fora de
#    `básico (< U+2500) + {✓ ◐ ○}` — é o conjunto fechado de D-R10; emoji
#    (✅ U+2705, ❌, U+1F3xx…) introduzido depois falha nomeando char e origem.
RSpec.describe 'commissioning-report — sweeps de i18n e glifos', :tenancy, type: :request do
  describe 'i18n (D14) — chaves usadas × locale' do
    RPTSW_SOURCES = %w[
      app/services/reports/commissioning_report_service.rb
    ].freeze

    it 'toda chave t(:...) dos serviços do relatório existe em report.v1.*' do
      keys = RPTSW_SOURCES.flat_map do |f|
        File.read(Rails.root.join(f)).scan(/\bt\(:(\w+)/).flatten
      end.uniq
      expect(keys).not_to be_empty
      missing = keys.reject { |k| I18n.exists?("report.v1.#{k}") }
      expect(missing).to eq([]), "chaves sem tradução em report.v1: #{missing.inspect}"
    end

    it 'nenhuma chave do locale interpola faltando argumento (todas resolvem)' do
      tree = I18n.t('report.v1')
      args = { from: 1, to: 2, count: 3, max: 4, projects: 1, cells: 1, robots: 1, tasks: 1 }
      tree.each_key do |k|
        expect { I18n.t("report.v1.#{k}", **args, raise: true) }.not_to raise_error
      end
    end
  end

  describe 'glifos (§5.1/D-R10) — conjunto fechado no payload' do
    let(:owner) { create(:user, name: 'Ana Dona') }
    let(:ws)    { make_workspace(owner: owner) }

    RPTSW_ALLOWED_HIGH = %w[✓ ◐ ○].freeze # únicos chars ≥ U+2500 admitidos (— é U+2014)

    def offending_chars(node, path = '$', acc = [])
      case node
      when Hash  then node.each { |k, v| offending_chars(v, "#{path}.#{k}", acc) }
      when Array then node.each_with_index { |v, i| offending_chars(v, "#{path}[#{i}]", acc) }
      when String
        node.each_char do |ch|
          acc << [ch, path] if ch.ord >= 0x2500 && !RPTSW_ALLOWED_HIGH.include?(ch)
        end
      end
      acc
    end

    it 'payload real e locale inteiro sem caractere fora de {✓ ◐ ○ —} + texto básico' do
      in_workspace(ws) do
        Person.create!(name: 'Ana', user_id: owner.id)
        p = Project.create!(name: 'Linha A', position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
        %w[Concluído Pendente N/A].each_with_index do |st, i|
          create_task(r, desc: "T#{i}", position: i, status: st, progress: st == 'Concluído' ? 100 : 0)
        end
      end
      get '/api/v1/commissioning_report?scope=all',
          headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
      bad = offending_chars(JSON.parse(response.body))
      expect(bad).to eq([]), "caracteres fora do conjunto no payload: #{bad.inspect}"

      bad_locale = offending_chars(I18n.t('report.v1').transform_keys(&:to_s))
      expect(bad_locale).to eq([]), "caracteres fora do conjunto no locale: #{bad_locale.inspect}"
    end
  end
end
