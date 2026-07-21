# frozen_string_literal: true

# §4.1 linhas 1 e 3 — avanço de progresso: view lê, owner/edit registram.
class AdvancePolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :record_progress
end
