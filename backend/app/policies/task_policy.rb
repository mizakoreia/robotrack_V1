# frozen_string_literal: true

# §4.1 linhas 1-3: tarefa é comissionamento; atribuir responsável é da linha
# "registrar avanço / atribuir / reordenar" (record_progress).
class TaskPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_commissioning,
          update?: :manage_commissioning,
          destroy?: :manage_commissioning,
          assign?: :record_progress
end
