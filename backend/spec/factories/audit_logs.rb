# frozen_string_literal: true

# audit-log 3.1 — factory de conveniência. `workspace_id` é auto-atribuído pelo
# WorkspaceScoped a partir do contexto de tenant (use dentro de `in_workspace`);
# passe `workspace_id:` explícito fora de contexto.
FactoryBot.define do
  factory :audit_log do
    id { SecureRandom.uuid }
    event_type { 'task_completed' }
    format_version { 1 }
    msg { 'Em [R-01], Ana concluiu a tarefa "T" com 100%.' }
    ts { Time.current }
    ts_local { '01/01/2026 00:00' }
    by_name { 'Ana' }
    payload { {} }
  end
end
