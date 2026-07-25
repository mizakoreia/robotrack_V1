# frozen_string_literal: true

# A matriz §4.1 da ESPECIFICACAO.md como DADO, não como código (D3.2).
#
# Nove chaves, uma por linha da tabela, NA MESMA ORDEM. Toda policy de recurso
# decide invocando `allows?` com uma destas actions; nenhuma policy compara
# papel diretamente (o cop do grupo 6 reprova `role ==` fora deste arquivo).
# O spec `spec/policies/permission_matrix_spec.rb` reafirma as linhas
# literalmente — mudar a matriz exige mudar dois lugares de propósito.
#
# `destroy_commissioning` (owner-only) separa o EXCLUIR do resto do
# comissionamento (owner-only-card-delete): criar/editar/reordenar/atribuir ficam
# em owner+edit (`manage_commissioning`/`record_progress`), mas excluir
# projeto/célula/robô/tarefa é só do dono.
module PermissionMatrix
  ACTIONS = {
    read_workspace:         %i[owner edit view],
    manage_commissioning:   %i[owner edit],
    destroy_commissioning:  %i[owner],
    record_progress:        %i[owner edit],
    manage_catalog:         %i[owner edit],
    create_log:             %i[owner edit],
    mark_notification_read: %i[owner edit view],
    manage_membership:      %i[owner],
    destroy_workspace:      %i[owner]
  }.freeze

  # Action desconhecida levanta KeyError — nunca `false` silencioso: um typo em
  # policy nova tem de explodir no primeiro teste, não virar negação misteriosa.
  def self.allows?(action, role)
    ACTIONS.fetch(action).include?(role&.to_sym)
  end
end
