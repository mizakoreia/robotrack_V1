# frozen_string_literal: true

require 'digest'
require 'json'

# legacy-data-migration — os pontos de entrada operacionais do porte do legado:
# `normalize` (G3), `import`/`import[,true]` dry-run/`rollback` (G2/G8). A ordem do
# corte (runbook) vive em `delivery-and-observability/RUNBOOK-legacy-cutover.md`.
namespace :legacy do
  desc 'Importa (ou dry-run) um canônico v1: rake legacy:import[<arquivo>,<dry_run true|false>]'
  task :import, %i[arquivo dry_run] => :environment do |_t, args|
    arquivo = args[:arquivo] or abort('uso: rake legacy:import[<arquivo.json>,<dry_run true|false>]')
    dry = args[:dry_run].to_s == 'true'
    canonical = JSON.parse(File.read(arquivo, encoding: 'UTF-8'))

    begin
      Legacy::ImportGuards.verify_schema_version!(canonical)
      Legacy::ImportGuards.validate_schema!(canonical)
    rescue Legacy::ImportGuards::SchemaVersionError, Legacy::ImportGuards::SchemaError => e
      abort("import recusado (nenhuma escrita): #{e.message}")
    end

    if dry
      report = Legacy::ImportService.dry_run(canonical: canonical)
      puts 'DRY-RUN (nada escrito):'
      print_report(report)
      next
    end

    ws_id = ENV['LEGACY_IMPORT_WORKSPACE_ID'] or abort('defina LEGACY_IMPORT_WORKSPACE_ID (workspace de destino)')
    sha = Digest::SHA256.file(arquivo).hexdigest
    force = ENV['LEGACY_IMPORT_FORCE'].to_s == 'true'
    run = nil
    begin
      Tenant.with(workspace_id: ws_id, user_id: nil) do
        Legacy::ImportContext.verify_sha256!(workspace_id: ws_id, file_sha256: sha, force: force)
        run = LegacyImportRun.create!(workspace_id: ws_id, legacy_owner_uid: canonical.dig('workspace', 'ownerUid'),
                                      file_sha256: sha, status: 'pending')
        Legacy::BackupService.call(run: run) # backup ANTES de qualquer escrita (D-LDM-6)
      end
    rescue Legacy::ImportContext::Sha256Mismatch, Legacy::ImportContext::ProvenanceError, Legacy::BackupService::Error => e
      abort("import recusado antes da 1ª escrita: #{e.message}")
    end

    report = Legacy::ImportService.call(canonical: canonical, run: run)
    puts "import concluído (run #{run.id}):"
    print_report(report)
  end

  def print_report(report)
    puts "  criados:    #{report.created.to_h}"
    puts "  pulados:    #{report.skipped.to_h}" if report.skipped.any?
    puts "  quarentena: #{report.quarantine.size} (#{report.quarantine.map { |q| q['reason'] }.tally})"
    puts "  avisos:     #{report.warnings.map { |w| w['reason'] }.tally}" if report.warnings.any?
  end

  desc 'Pré-processa o export bruto no canônico v1 (rake legacy:normalize[<entrada>,<saida>])'
  task :normalize, %i[entrada saida] => :environment do |_t, args|
    entrada = args[:entrada] or abort('uso: rake legacy:normalize[<entrada.json>,<saida.json>]')
    saida   = args[:saida] or abort('uso: rake legacy:normalize[<entrada.json>,<saida.json>]')

    begin
      report = Legacy::NormalizeExportService.call(input_path: entrada, output_path: saida)
    rescue Legacy::NormalizeExportService::Error => e
      abort("normalize falhou (nenhum arquivo escrito): #{e.message}")
    end

    puts "canônico escrito em #{saida}"
    puts "  migracoes_aplicadas: #{report[:migracoes_aplicadas]}" \
         " (substituem as migrações de runtime de §4.4)"
    puts "  sentinela_removido:  #{report[:sentinela_removido]}"
    puts "  entrada_ja_canonica: #{report[:entrada_ja_canonica]}"
  end

  desc 'Valida §2.1 de uma amostra adversarial contra o export (rake legacy:validate_sample[<arquivo>,<ws>])'
  task :validate_sample, %i[arquivo workspace_id] => :environment do |_t, args|
    arquivo = args[:arquivo] or abort('uso: rake legacy:validate_sample[<arquivo.json>,<workspace_id>]')
    ws_id = args[:workspace_id] or abort('uso: rake legacy:validate_sample[<arquivo.json>,<workspace_id>]')
    canonical = JSON.parse(File.read(arquivo, encoding: 'UTF-8'))
    sample = Legacy::SampleValidator.select_sample(canonical)

    divergences = nil
    Tenant.with(workspace_id: ws_id, user_id: nil) do
      Progress::BulkRecompute.call(workspace_id: ws_id) # progress_cache tem de estar corrente
      divergences = Legacy::SampleValidator.diffs(sample)
    end

    if divergences.any?
      puts "VALIDAÇÃO REPROVADA — #{divergences.size}/#{sample.size} robô(s) divergente(s):"
      divergences.each { |d| puts "  #{d[:legacy_path]}: esperado #{d[:expected]}, banco #{d[:actual]}" }
      abort('recomendado: rake legacy:rollback[<run_id>] e voltar ao dry-run (runbook passo 5)')
    end
    puts "validação OK — #{sample.size} robôs amostrados, diferença zero"
  end

  desc 'Desfaz um run de import legado por legacy_id_map (rake legacy:rollback[<run_id>])'
  task :rollback, [:run_id] => :environment do |_t, args|
    run_id = args[:run_id] or abort('uso: rake legacy:rollback[<run_id>]')

    run = LegacyImportRun.unscoped.find_by(id: run_id)
    abort("run não encontrado: #{run_id}") unless run

    report = Legacy::RollbackService.call(run: run)

    puts "rollback do run #{run.id} (workspace #{run.workspace_id}) concluído:"
    puts "  arquivados: #{report[:archived].to_h}"
    puts "  deletados:  #{report[:deleted].to_h}"
    puts "  pulados:    #{report[:skipped].to_h}" if report[:skipped].any?
  end
end
