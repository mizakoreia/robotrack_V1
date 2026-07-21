# frozen_string_literal: true

# robot-tasks 2.3 (§1.1, D-RT-1, D10/D11) — a atribuição de um responsável
# (`person_id`) a uma tarefa. Uma linha por par; ausência de responsável é a
# AUSÊNCIA de linhas, nunca uma pessoa sentinela.
#
# As invariantes moram no banco: unicidade `(task_id, person_id)`, coerência de
# tenant pelas FKs compostas, isolamento por RLS. O model é a ergonomia.
class TaskAssignee < ApplicationRecord
  include WorkspaceScoped

  belongs_to :task
  belongs_to :person
end
