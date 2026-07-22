# frozen_string_literal: true

# audit-log 1.2 — chama o guard de imutabilidade SÓ num processo de runtime
# (servidor web ou worker Sidekiq). Migração, console, rake e a suíte conectam
# como o DONO (que tem UPDATE de propósito) e NÃO devem abortar. A verificação real
# do privilégio do papel de app é o spec 1.3.
Rails.application.config.after_initialize do
  server_process = defined?(Rails::Server) || (defined?(Sidekiq) && Sidekiq.server?)
  next unless server_process

  begin
    AuditLog::ImmutabilityGuard.enforce!
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn({ event: 'audit_immutability_guard_skipped', error: e.message }.to_json)
  end
end
