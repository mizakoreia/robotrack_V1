# frozen_string_literal: true

# legacy-data-migration 2.4 (D-LDM-6, D12) — o `rake legacy:rollback` grava UMA entrada
# em `audit_logs` provando que o rollback ocorreu (a trilha imutável não é apagada; as
# entradas importadas ficam — inconsistência deliberada de D-LDM-6). Para isso o evento
# precisa passar pela CHECK de `event_type`, hoje restrita a `task_completed`/
# `workspace_reset`. Adicionamos `legacy_rollback`.
#
# `audit_logs` é PARTICIONADA por RANGE(ts): `ALTER TABLE <parent> DROP/ADD CONSTRAINT`
# propaga a todas as partições (PG 11+). O texto renderizado (`AuditLog::RecordService` +
# locale `audit.legacy_rollback.v1`) é congelado na linha no INSERT, como os demais.
class AddLegacyRollbackAuditEvent < ActiveRecord::Migration[8.0]
  OLD = "event_type IN ('task_completed', 'workspace_reset')"
  NEW = "event_type IN ('task_completed', 'workspace_reset', 'legacy_rollback')"

  def up
    swap_check(NEW)
  end

  def down
    # Reverter só é seguro se nenhum rollback legado foi registrado (ADD CONSTRAINT
    # valida as linhas existentes). Em dev/test a tabela está vazia; em produção,
    # depois do 1º legacy_rollback, isto falharia — e é o comportamento correto
    # (não se estreita a auditoria retroativamente).
    swap_check(OLD)
  end

  private

  def swap_check(predicate)
    execute(<<~SQL)
      ALTER TABLE audit_logs DROP CONSTRAINT chk_audit_event_type;
      ALTER TABLE audit_logs ADD  CONSTRAINT chk_audit_event_type CHECK (#{predicate});
    SQL
  end
end
