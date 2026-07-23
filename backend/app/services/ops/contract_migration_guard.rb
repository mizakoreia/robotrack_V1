# frozen_string_literal: true

module Ops
  # Guarda de migration expand/contract (delivery-and-observability 8.1/8.2). Uma
  # operação DESTRUTIVA (`remove_column`/`drop_table`/`change_column`/
  # `rename_column`) sem o marcador `# contract-of: <versão>` reprova o CI: sem o
  # marcador, um rollback de CÓDIGO não sabe que o ESQUEMA já foi contraído e
  # quebraria. O marcador declara "esta contração assume que a versão <X> já não
  # depende mais da coluna".
  #
  # Linha de corte: as migrations legadas do template (<= CUTOFF) são grandfathered
  # — exigir o marcador retroativamente reprovaria migrations que não podem mudar.
  # A regra vale a partir daqui.
  module ContractMigrationGuard
    CUTOFF_VERSION = '20260723160001'
    DESTRUCTIVE = /\b(remove_column|drop_table|change_column|rename_column)\b/
    MARKER = /#\s*contract-of:\s*\S+/

    module_function

    def migration_version(path)
      File.basename(path)[/\A(\d+)_/, 1]
    end

    # Migrations posteriores ao corte com operação destrutiva e SEM marcador.
    def offenders(migrate_dir)
      Dir.glob(File.join(migrate_dir, '*.rb')).select do |path|
        version = migration_version(path)
        next false unless version && version > CUTOFF_VERSION

        content = File.read(path)
        content.match?(DESTRUCTIVE) && !content.match?(MARKER)
      end
    end

    # Um arquivo específico é uma migration de contração marcada?
    def contract?(path)
      content = File.read(path)
      content.match?(DESTRUCTIVE) && content.match?(MARKER)
    end
  end
end
