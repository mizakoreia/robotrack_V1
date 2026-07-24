# frozen_string_literal: true

# `class AuditLog` (não `module`): o model define a classe e serve de namespace
# explícito (Zeitwerk carrega o model antes deste arquivo aninhado).
class AuditLog
  # audit-log 1.2 (Decisão 1, plano de migração passo 3) — a rede de deploy: se o
  # processo de RUNTIME (Puma/Sidekiq) subir com a credencial do papel DONO em vez
  # de `robotrack_app`, a camada 1 (REVOKE) fica inerte e a imutabilidade passa a
  # depender só da trigger. Este guard recusa subir nesse caso, nomeando a tabela e
  # o privilégio.
  #
  # NÃO roda em migração/console/rake/suite (o dono LEGITIMAMENTE tem UPDATE ali): o
  # initializer só chama `enforce!` num processo de servidor/worker. A garantia
  # determinística de que o papel de app não tem o privilégio é do spec de privilégio
  # (1.3), não deste guard.
  module ImmutabilityGuard
    module_function

    # true se ESTE processo ATENDE tráfego de runtime (conecta como robotrack_app),
    # onde a imutabilidade importa. Migração/console/rake/suite conectam como o DONO
    # (UPDATE legítimo) e devem devolver false para o boot NÃO abortar.
    #
    #   web    → `bundle exec puma`    → basename($0) == 'puma'  ← ramo do BUG 11
    #   worker → `bundle exec sidekiq` → Sidekiq.server?
    #   dev    → `rails server`        → defined?(Rails::Server)
    #
    # O ramo `puma` é o conserto do BUG 11: em produção o web sobe por `bundle exec
    # puma`, que NUNCA define `Rails::Server` (só `rails server` o faz). Sem ele o
    # guard ficava inerte justo no processo que atende TODAS as escritas. Argumentos
    # injetáveis só para o teste; em runtime lê os sinais reais do processo.
    def runtime_server_process?(program_name: $PROGRAM_NAME,
                                sidekiq_server: (defined?(Sidekiq) && Sidekiq.server?),
                                rails_server: defined?(Rails::Server))
      return true if rails_server
      return true if sidekiq_server

      File.basename(program_name.to_s) == 'puma'
    end

    # true se o papel corrente enxerga UPDATE sobre audit_logs (= subiu como dono).
    def violated?(connection = ActiveRecord::Base.connection)
      return false if connection.select_value("SELECT to_regclass('public.audit_logs')::text").nil?

      connection.select_value(
        "SELECT has_table_privilege(current_user, 'audit_logs', 'UPDATE')"
      )
    end

    def enforce!(connection = ActiveRecord::Base.connection)
      return unless violated?(connection)

      abort(
        '[audit-log] BOOT ABORTADO: o papel corrente tem privilégio UPDATE sobre ' \
        'audit_logs — o runtime subiu com a credencial do DONO, não com robotrack_app. ' \
        'A imutabilidade append-only (§4.1 inv. 3) fica comprometida. Aponte ' \
        'DATABASE_URL para robotrack_app.'
      )
    end
  end
end
