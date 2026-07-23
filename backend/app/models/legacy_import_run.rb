# frozen_string_literal: true

# legacy-data-migration 2.1 (D-LDM-2, D-LDM-6) — o registro de uma execução da
# importação legada. `file_sha256` é o que a 8.4 usa para recusar reimportar um
# arquivo diferente num workspace já importado; `backup_path` aponta o `pg_dump -Fc`
# da rede de segurança grossa (2.3); `report` guarda criados/pulados/quarentena por
# entidade. É também o namespace de `Legacy::*` services que operam sobre um run.
class LegacyImportRun < ApplicationRecord
  include WorkspaceScoped

  has_many :id_map_entries, class_name: 'LegacyIdMap', foreign_key: :run_id,
                            inverse_of: :run, dependent: :destroy

  STATUSES = %w[pending completed failed rolled_back].freeze

  validates :legacy_owner_uid, presence: true
  validates :file_sha256, presence: true
  validates :status, inclusion: { in: STATUSES }
end
