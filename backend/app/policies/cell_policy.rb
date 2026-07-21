# frozen_string_literal: true

# §4.1 linhas 1-2 — célula é recurso de comissionamento.
class CellPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_commissioning,
          update?: :manage_commissioning,
          destroy?: :manage_commissioning,
          reorder?: :record_progress
end
