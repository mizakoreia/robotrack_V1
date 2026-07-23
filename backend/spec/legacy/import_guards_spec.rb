# frozen_string_literal: true

require 'rails_helper'
require 'json'

# legacy-data-migration 8.3/8.4/8.5 (D-LDM-2, D-LDM-5, D-LDM-8) — as guardas do corte:
# dry-run que não escreve, recusa de sha256 divergente e o contrato de schemaVersion.
RSpec.describe 'Legacy — guardas do corte (dry-run, sha256, schemaVersion)', :tenancy, type: :model do
  let(:canonical) do
    JSON.parse(File.read(Rails.root.join('spec/fixtures/legacy/canonical_v1.json'), encoding: 'UTF-8'))
  end

  # === 8.3 dry-run ===
  describe 'dry-run não escreve e prevê a quarentena' do
    it 'conta por entidade e prevê a quarentena SEM criar nenhuma linha' do
      before_projects = Project.unscoped.count
      report = Legacy::ImportService.dry_run(canonical: canonical)

      expect(report.created['project']).to eq(4)
      expect(report.created['robot']).to eq(4)
      expect(report.created['task']).to eq(8)
      expect(report.quarantine.map { |q| q['reason'] })
        .to include('application_fora_do_enum', 'progress_fora_da_faixa', 'status_fora_do_enum')

      # Nada foi escrito: nenhum projeto novo, nenhum run.
      expect(Project.unscoped.count).to eq(before_projects)
      expect(Project.unscoped.where(id: Legacy::IdDerivation.project_id('ws-legacy-1', 'p-1'))).to be_empty
    end
  end

  # === 8.4 recusa de sha256 divergente ===
  describe 'recusa de reimport com sha256 diferente' do
    let(:ws) { make_workspace(name: 'WS Sha') }

    before do
      in_workspace(ws) do
        LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u', file_sha256: 'a' * 64, status: 'completed')
      end
    end

    it 'recusa arquivo de sha diferente sem --force, citando os dois hashes' do
      in_workspace(ws) do
        expect { Legacy::ImportContext.verify_sha256!(workspace_id: ws.id, file_sha256: 'b' * 64) }
          .to raise_error(Legacy::ImportContext::Sha256Mismatch, /#{'a' * 64}.*#{'b' * 64}|--force/m)
      end
    end

    it 'aceita com --force e aceita o mesmo sha' do
      in_workspace(ws) do
        expect { Legacy::ImportContext.verify_sha256!(workspace_id: ws.id, file_sha256: 'b' * 64, force: true) }.not_to raise_error
        expect { Legacy::ImportContext.verify_sha256!(workspace_id: ws.id, file_sha256: 'a' * 64) }.not_to raise_error
      end
    end
  end

  # === 8.5 contrato de schemaVersion + validação de schema ===
  describe 'contrato de schemaVersion (duas pontas)' do
    it 'aceita schemaVersion 1' do
      expect { Legacy::ImportGuards.verify_schema_version!(canonical) }.not_to raise_error
    end

    it 'recusa schemaVersion 2 citando a versão suportada 1' do
      expect { Legacy::ImportGuards.verify_schema_version!(canonical.merge('schemaVersion' => 2)) }
        .to raise_error(Legacy::ImportGuards::SchemaVersionError, /suportada: 1|schemaVersion 2/)
    end

    it 'trata arquivo SEM schemaVersion como bruto e manda normalizar' do
      expect { Legacy::ImportGuards.verify_schema_version!(canonical.except('schemaVersion')) }
        .to raise_error(Legacy::ImportGuards::SchemaVersionError, /normalize/i)
    end

    it 'valida o canônico contra o schema e rejeita application numérica citando o caminho' do
      expect { Legacy::ImportGuards.validate_schema!(canonical) }.not_to raise_error
      bad = canonical.dup
      bad['projects'][0]['cells'][0]['robots'][0]['application'] = 42
      expect { Legacy::ImportGuards.validate_schema!(bad) }
        .to raise_error(Legacy::ImportGuards::SchemaError, /application/i)
    end
  end
end
