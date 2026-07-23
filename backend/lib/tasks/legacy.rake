# frozen_string_literal: true

# legacy-data-migration — os pontos de entrada operacionais do porte do legado.
# G2 entrega o `rollback` (a rede fina de D-LDM-6). `normalize`/`import`/
# `validate_sample` chegam nos grupos seguintes (G3/G8).
namespace :legacy do
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
