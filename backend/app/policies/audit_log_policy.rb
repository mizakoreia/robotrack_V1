# frozen_string_literal: true

# §4.1 linhas 1 e 5, inv. 3 (D3.9): log de auditoria é append-only para TODOS,
# inclusive o dono. `update?`/`destroy?` NÃO existem de propósito —
# `respond_to?(:update?)` é false, não um método que retorna false. O mecanismo
# primário (REVOKE UPDATE, DELETE) é da capacidade `audit-log`; a suíte de
# invariantes falha enquanto ele não existir.
class AuditLogPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :create_log
end
