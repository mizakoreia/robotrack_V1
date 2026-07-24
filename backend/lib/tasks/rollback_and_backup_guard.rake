# frozen_string_literal: true

# delivery-and-observability 8.1/8.3 — guardas de rollback e de backup para
# migration contract. O `db:rollback` passa a recusar contração destrutiva (não é
# reversível por migration — restaura-se do backup). O `bin/release` chama
# `ops:guard_contract_backup` antes de migrar: se há migration contract pendente e
# o backup está velho/ não-verificado, aborta ANTES de tocar o esquema.

def migration_path_for(version)
  Dir.glob(Rails.root.join("db/migrate/#{version}_*.rb")).first
end

namespace :ops do
  desc 'Recusa db:rollback de uma migration contract (8.1)'
  task refuse_contract_rollback: :environment do
    versions = ActiveRecord::Base.connection_pool.migration_context.get_all_versions
    unless versions.empty?
      path = migration_path_for(versions.max)
      if path && Ops::ContractMigrationGuard.contract?(path)
        abort(<<~MSG)
          [db:rollback RECUSADO] #{File.basename(path)} é uma migration `contract`.
          Rollback de esquema DESTRUTIVO não é reversível por migration — o dado já
          saiu. Restaure do backup verificado: ver docs/runbooks/rollback.md
          (degrau 3) e o RPO no manifesto do backup.
        MSG
      end
    end
  end

  desc 'Aborta migração contract quando o backup não é seguro (8.3)'
  task guard_contract_backup: :environment do
    ctx = ActiveRecord::Base.connection_pool.migration_context
    pending = ctx.migrations.map(&:version) - ctx.get_all_versions
    pending_contract = pending.map { |v| migration_path_for(v) }.compact.select { |p| Ops::ContractMigrationGuard.contract?(p) }
    next if pending_contract.empty?

    manifest_path = ENV['BACKUP_MANIFEST']
    backup = manifest_path && File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path), symbolize_names: true) : nil
    backup[:taken_at] = Time.parse(backup[:taken_at]) if backup && backup[:taken_at].is_a?(String)

    begin
      Ops::VerifiedBackup.assert_safe_for_contract!(backup: backup)
      puts "[release] backup verificado OK para #{pending_contract.size} migration(s) contract"
    rescue RuntimeError => e
      abort("[release] #{e.message}")
    end
  end
end

Rake::Task['db:rollback'].enhance(['ops:refuse_contract_rollback']) if Rake::Task.task_defined?('db:rollback')
