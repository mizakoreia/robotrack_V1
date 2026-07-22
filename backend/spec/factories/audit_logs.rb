# frozen_string_literal: true

# audit-log 3.1 — SEM factory de propósito (reconciliação hierarchy-soft-delete G4).
#
# `AuditLog` é model de tenant: sob RLS, `create(:audit_log)` FORA de um
# `in_workspace` (como faz o `factories_spec` genérico, que roda toda factory sem
# contexto) tem `workspace_id` nulo e estoura no NOT NULL/`WITH CHECK`. É a MESMA
# razão pela qual `projects`/`cells`/`robots`/`tasks` não têm factory (ver o
# comentário de `spec/support/tenancy_helpers.rb`): linhas de tenant nascem por
# helper dentro de contexto, não por FactoryBot. A factory anterior era código
# MORTO (nenhum spec a usava) e quebrava o `factories_spec` desde `audit-log` G2 —
# falha só exposta agora, na primeira suíte COMPLETA desde então. Removida.
