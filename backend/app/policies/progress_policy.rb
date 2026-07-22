# frozen_string_literal: true

# progress-rollup 4.5 (§4.1 inv. 4, D3) — recalcular o cache do workspace é uma
# MUTAÇÃO: exige `record_progress` (owner/edit). `view` recebe 403 e nenhum
# UPDATE em `progress_cache` é emitido. Decisão sai da PermissionMatrix.
class ProgressPolicy < BasePolicy
  permits recompute?: :record_progress
end
