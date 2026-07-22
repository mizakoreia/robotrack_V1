# frozen_string_literal: true

# my-tasks-view 3.3 (§4.1, D-MTV-10) — a policy de "Minhas Tarefas".
#
# Exige apenas membership ATIVA no workspace, em QUALQUER papel — inclusive `view`.
# §4.1 inv. 4 restringe *mutações* de um membro `view`, e esta tela não muta nada;
# ler as PRÓPRIAS tarefas é leitura pura (`read_workspace`). Não há verificação de
# "posso ver as tarefas de X": o único X possível é o próprio viewer, derivado do
# token, NUNCA de um parâmetro (D-MTV-10). Não-membro → o gate resolve papel nil e
# NEGA a policy → 403 (esta é coleção, sem `:id`; o 404 de D3.6 é para recurso
# RLS-invisível resolvido por `find_by`, que aqui não existe).
class MyTasksPolicy < BasePolicy
  permits index?: :read_workspace
end
