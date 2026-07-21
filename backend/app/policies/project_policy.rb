# frozen_string_literal: true

# §4.1 linhas 1-3: view lê tudo; criar/editar/excluir comissionamento é
# owner/edit; reordenar é da linha "registrar avanço/atribuir/reordenar".
class ProjectPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_commissioning,
          update?: :manage_commissioning,
          destroy?: :manage_commissioning,
          reorder?: :record_progress
end
