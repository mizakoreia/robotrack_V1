# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# legacy-data-migration 2.3 (D-LDM-6) — a rede de segurança GROSSA recusa iniciar
# ANTES da primeira escrita se o backup não puder ser feito. O modo de falha que
# isto guarda: começar a importar, escrever metade, e só então descobrir que não há
# para onde voltar. As checagens de diretório rodam sem `pg_dump` (nada de banco).
RSpec.describe 'Legacy::BackupService — recusa antes da 1ª escrita', :tenancy, type: :model do
  let(:run) do
    ws = make_workspace(name: 'WS Backup')
    in_workspace(ws) do
      LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u', file_sha256: 'b' * 64)
    end
  end

  it 'recusa quando LEGACY_IMPORT_BACKUP_DIR não está definido' do
    expect { Legacy::BackupService.call(run: run, backup_dir: nil) }
      .to raise_error(Legacy::BackupService::Error, /não definido/i)
  end

  it 'recusa quando o diretório não existe' do
    expect { Legacy::BackupService.call(run: run, backup_dir: '/caminho/que/nao/existe/xyz') }
      .to raise_error(Legacy::BackupService::Error, /não existe/i)
  end

  it 'recusa quando o diretório não é gravável (aborta antes de qualquer pg_dump)' do
    skip 'rodando como root: access() ignora o bit de permissão' if Process.uid.zero?

    Dir.mktmpdir do |dir|
      File.chmod(0o500, dir) # r-x: leitura sim, escrita não
      expect { Legacy::BackupService.call(run: run, backup_dir: dir) }
        .to raise_error(Legacy::BackupService::Error, /não é gravável/i)
    ensure
      File.chmod(0o700, dir)
    end
  end
end
