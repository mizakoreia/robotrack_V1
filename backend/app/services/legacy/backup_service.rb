# frozen_string_literal: true

module Legacy
  # legacy-data-migration 2.3 (D-LDM-6) — a rede de segurança GROSSA: um `pg_dump -Fc`
  # do banco ANTES de qualquer escrita do import. O run **recusa iniciar** se o
  # diretório de backup não existir/não for gravável ou se o dump falhar — a recusa
  # acontece ANTES da primeira escrita (o `count(*)` de `projects` fica inalterado).
  #
  # Não roda sob RLS (é `pg_dump`, um processo externo com as credenciais do banco);
  # o único efeito no schema é gravar `backup_path` no run (isso sim sob o contexto de
  # tenant que o chamador já abriu). Formato `-Fc` (custom) porque é o que `pg_restore`
  # seletivo consome — a rede fina (rollback por run) é o caminho comum; este é o
  # "voltar tudo" de última instância.
  module BackupService
    Error = Class.new(StandardError)

    module_function

    # run:        o LegacyImportRun (recebe backup_path em caso de sucesso).
    # backup_dir: diretório de destino (default ENV['LEGACY_IMPORT_BACKUP_DIR']).
    # Devolve o caminho do dump. Levanta Legacy::BackupService::Error antes de
    # qualquer escrita se o pré-requisito falhar.
    def call(run:, backup_dir: ENV.fetch('LEGACY_IMPORT_BACKUP_DIR', nil))
      dir = ensure_writable_dir!(backup_dir)
      path = File.join(dir, "legacy_import_#{run.id}.dump")

      run_pg_dump!(path)

      run.update!(backup_path: path)
      path
    end

    def ensure_writable_dir!(backup_dir)
      raise Error, 'LEGACY_IMPORT_BACKUP_DIR não definido — o import recusa iniciar sem backup (D-LDM-6)' if backup_dir.to_s.strip.empty?

      dir = File.expand_path(backup_dir)
      raise Error, "diretório de backup não existe: #{dir}" unless File.directory?(dir)
      raise Error, "diretório de backup não é gravável: #{dir}" unless File.writable?(dir)

      dir
    end

    def run_pg_dump!(path)
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      args = ['pg_dump', '-Fc', '-f', path,
              '-h', cfg[:host].to_s, '-p', cfg[:port].to_s,
              '-U', cfg[:username].to_s, '-d', cfg[:database].to_s]
      env = cfg[:password] ? { 'PGPASSWORD' => cfg[:password].to_s } : {}

      ok = system(env, *args.reject { |a| a == '-h' && cfg[:host].to_s.empty? }, out: File::NULL, err: File::NULL)
      raise Error, "pg_dump falhou (comando: #{args.first(3).join(' ')} …) — nada foi importado" unless ok
    end
  end
end
