# frozen_string_literal: true

require 'rails_helper'
require 'json-schema'
require 'json'

# MultiJSON mangla o UTF-8 das fixtures acentuadas; força o parser JSON puro.
JSON::Validator.use_multi_json = false

# legacy-data-migration 1.3 (D-LDM-8) — o schema do export canônico v1 é o contrato de
# DUAS pontas: nós validamos contra ele antes de importar; workspace-settings §3.11 emite
# contra ele. O teste prova que a fixture canônica PASSA e a bruta (formato antigo, sem
# schemaVersion) FALHA — um schema que aceita as duas não é schema.
RSpec.describe 'legacy_export_v1.schema.json — contrato de arquivo', type: :model do
  SCHEMA = JSON.parse(File.read(Rails.root.join('config/legacy_export_v1.schema.json'), encoding: 'UTF-8'))
  FIX = Rails.root.join('spec/fixtures/legacy')

  def load_fixture(file)
    JSON.parse(File.read(FIX.join(file), encoding: 'UTF-8'))
  end

  def errors_for(file)
    # validate_schema: false — não revalidar o próprio schema contra a meta-schema
    # (a gem json-schema tropeça em draft-07 `const`; a validação do DADO é o que importa).
    JSON::Validator.fully_validate(SCHEMA, load_fixture(file), validate_schema: false)
  end

  it 'canonical_v1.json é válido contra o schema (incl. valores de quarentena — tipos ok)' do
    errs = errors_for('canonical_v1.json')
    expect(errs).to be_empty, "erros inesperados:\n#{errs.join("\n")}"
  end

  it 'raw_nested.json (sem schemaVersion, projetos aninhados) FALHA a validação' do
    errs = errors_for('raw_nested.json')
    expect(errs).not_to be_empty
    expect(errs.join(' ')).to match(/schemaVersion|required|projects/i)
  end

  it 'um robô com application numérica (tipo errado) é rejeitado citando o caminho' do
    doc = load_fixture('canonical_v1.json')
    doc['projects'][0]['cells'][0]['robots'][0]['application'] = 42
    errs = JSON::Validator.fully_validate(SCHEMA, doc, validate_schema: false)
    expect(errs.join(' ')).to match(/application/i)
  end
end
