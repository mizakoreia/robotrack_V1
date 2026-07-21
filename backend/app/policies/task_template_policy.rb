# frozen_string_literal: true

# §4.1 linhas 1 e 4 — catálogo de tarefas-base: view lê, owner/edit editam.
class TaskTemplatePolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_catalog,
          update?: :manage_catalog,
          destroy?: :manage_catalog
end
