# frozen_string_literal: true

require 'json-schema'
require 'json'

# MultiJSON mangla o UTF-8 acentuado; força o parser JSON puro (mesmo motivo de G1).
JSON::Validator.use_multi_json = false

module Legacy
  # legacy-data-migration 8.5 (D-LDM-8, §4.4, legacy-structural-migrations §"validação de
  # schema antes do import") — as guardas de CONTRATO que rodam ANTES de qualquer escrita:
  #   - `schemaVersion` DEVE ser 1. `2` (o que o exportador de §3.11 emite hoje — divergência
  #     anotada em G1) é recusado citando a versão suportada; AUSENTE → é bruto, manda rodar
  #     `legacy:normalize` primeiro.
  #   - o arquivo é validado contra `config/legacy_export_v1.schema.json` (o mesmo contrato de
  #     duas pontas de G1) — um `application: 42` falha citando o caminho, não com NoMethodError
  #     no meio do run.
  module ImportGuards
    SchemaVersionError = Class.new(StandardError)
    SchemaError = Class.new(StandardError)

    SUPPORTED_VERSION = 1
    SCHEMA_PATH = 'config/legacy_export_v1.schema.json'

    module_function

    def verify_schema_version!(canonical)
      version = canonical['schemaVersion']
      if version.nil?
        raise SchemaVersionError,
              'arquivo sem schemaVersion — é um export bruto; rode `rake legacy:normalize` primeiro'
      end
      return if version == SUPPORTED_VERSION

      raise SchemaVersionError, "schemaVersion #{version} não suportado — versão suportada: #{SUPPORTED_VERSION}"
    end

    def validate_schema!(canonical)
      errors = JSON::Validator.fully_validate(schema, canonical, validate_schema: false)
      return if errors.empty?

      raise SchemaError, "arquivo canônico inválido (nenhuma escrita feita):\n#{errors.join("\n")}"
    end

    def schema
      @schema ||= JSON.parse(File.read(Rails.root.join(SCHEMA_PATH), encoding: 'UTF-8'))
    end
  end
end
