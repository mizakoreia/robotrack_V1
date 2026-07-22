# frozen_string_literal: true

module AuditLog
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
