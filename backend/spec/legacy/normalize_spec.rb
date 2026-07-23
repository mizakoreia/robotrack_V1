# frozen_string_literal: true

require 'rails_helper'
require 'json-schema'
require 'json'
require 'digest'
require 'tmpdir'

JSON::Validator.use_multi_json = false

# legacy-data-migration 3.4 (§4.4, D-LDM-1, D-LDM-3 camada 1) — a prova do pré-processador:
# normaliza o bruto, valida a saída contra o schema v1, normaliza de novo e compara o
# SHA-256 (execução única, sem estado mutável de migração). Cobre também os cenários de
# promoção estrutural, procedência (`ownerUid`), remoção do sentinela e atomicidade.
RSpec.describe 'Legacy::NormalizeExportService — pré-processador §4.4', type: :model do
  NORM_SCHEMA = JSON.parse(File.read(Rails.root.join('config/legacy_export_v1.schema.json'), encoding: 'UTF-8'))
  NORM_RAW = Rails.root.join('spec/fixtures/legacy/raw_nested.json')

  def normalize(raw) = Legacy::NormalizeExportService.normalize(raw)
  def raw_nested = JSON.parse(File.read(NORM_RAW, encoding: 'UTF-8'))

  describe 'promoção estrutural (§4.4)' do
    it 'promove workspace.projects/logs a topo com workspaceId e remove as chaves aninhadas' do
      out = normalize(raw_nested)
      c = out[:canonical]

      expect(c['workspace']).not_to have_key('projects')
      expect(c['workspace']).not_to have_key('logs')
      expect(c['projects'].size).to eq(1)
      expect(c['projects'].first['workspaceId']).to eq('ws-legacy-1')
      expect(c['logs'].size).to eq(2)
      expect(c['logs'].map { |l| l['workspaceId'] }.uniq).to eq(['ws-legacy-1'])
      expect(out[:report][:migracoes_aplicadas]).to eq(2)
    end

    it 'export já no formato de topo não aplica migração (migracoes_aplicadas: 0)' do
      raw = { 'workspace' => { 'id' => 'w', 'ownerUid' => 'u', 'name' => 'N', 'responsibles' => [] },
              'projects' => [{ 'name' => 'P' }], 'logs' => [] }
      expect(normalize(raw)[:report][:migracoes_aplicadas]).to eq(0)
    end
  end

  describe 'contrato canônico' do
    it 'a primeira chave da saída é schemaVersion: 1' do
      c = normalize(raw_nested)[:canonical]
      expect(c.keys.first).to eq('schemaVersion')
      expect(c['schemaVersion']).to eq(1)
    end

    it 'a saída valida contra o schema v1' do
      c = normalize(raw_nested)[:canonical]
      errs = JSON::Validator.fully_validate(NORM_SCHEMA, c, validate_schema: false)
      expect(errs).to be_empty, errs.join("\n")
    end
  end

  describe 'procedência do dono (ownerUid)' do
    it 'ownerUid ausente aborta sem produzir canônico' do
      raw = raw_nested
      raw['workspace'].delete('ownerUid')
      expect { normalize(raw) }
        .to raise_error(Legacy::NormalizeExportService::Error, /ownerUid ausente/i)
    end

    it 'ownerUid é propagado para o canônico' do
      raw = raw_nested
      raw['workspace']['ownerUid'] = 'u-123'
      expect(normalize(raw)[:canonical]['workspace']['ownerUid']).to eq('u-123')
    end
  end

  describe 'sentinela "Não Atribuído" (D-LDM-3 camada 1)' do
    it 'sai de responsibles, de assignees e de resp' do
      raw = {
        'workspace' => {
          'id' => 'w', 'ownerUid' => 'u', 'name' => 'N',
          'responsibles' => ['Não Atribuído', 'Ana', 'Bruno']
        },
        'projects' => [{
          'name' => 'P', 'cells' => [{ 'name' => 'C', 'robots' => [{
            'name' => 'R', 'application' => 'Handling', 'tasks' => [
              { 'cat' => 'A', 'desc' => 'T1', 'assignees' => ['Não Atribuído', 'Ana'], 'resp' => 'Não Atribuído' }
            ]
          }] }]
        }]
      }
      out = normalize(raw)
      c = out[:canonical]
      expect(c['workspace']['responsibles']).to eq(%w[Ana Bruno])
      task = c['projects'][0]['cells'][0]['robots'][0]['tasks'][0]
      expect(task['assignees']).to eq(['Ana'])
      expect(task['resp']).to be_nil
      expect(out[:report][:sentinela_removido]).to eq(3)
    end
  end

  describe 'atomicidade (D-LDM-1)' do
    it 'log sem ts aborta e não deixa arquivo de saída' do
      Dir.mktmpdir do |dir|
        raw = { 'workspace' => { 'id' => 'w', 'ownerUid' => 'u', 'name' => 'N',
                                 'logs' => [{ 'eventType' => 'x' }] }, 'projects' => [] }
        input = File.join(dir, 'in.json')
        output = File.join(dir, 'out.json')
        File.write(input, JSON.generate(raw))

        expect { Legacy::NormalizeExportService.call(input_path: input, output_path: output) }
          .to raise_error(Legacy::NormalizeExportService::Error, /ts/)
        expect(File.exist?(output)).to be(false)
        expect(Dir.glob("#{output}*")).to be_empty # nem o temporário
      end
    end
  end

  describe 'execução única (idempotência)' do
    it 'normalize duas vezes produz bytes idênticos e a 2a reporta entrada_ja_canonica' do
      Dir.mktmpdir do |dir|
        a = File.join(dir, 'a.json')
        b = File.join(dir, 'b.json')

        Legacy::NormalizeExportService.call(input_path: NORM_RAW.to_s, output_path: a)
        report_b = Legacy::NormalizeExportService.call(input_path: a, output_path: b)

        expect(Digest::SHA256.file(a).hexdigest).to eq(Digest::SHA256.file(b).hexdigest)
        expect(report_b[:migracoes_aplicadas]).to eq(0)
        expect(report_b[:entrada_ja_canonica]).to be(true)
      end
    end
  end
end
