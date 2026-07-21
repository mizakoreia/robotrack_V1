# frozen_string_literal: true

# §4.1 linhas 1 e 4 — responsáveis fazem parte do catálogo do workspace.
class PersonPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_catalog,
          update?: :manage_catalog,
          destroy?: :manage_catalog
end
