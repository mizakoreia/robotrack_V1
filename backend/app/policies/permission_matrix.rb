# frozen_string_literal: true

# A matriz §4.1 da ESPECIFICACAO.md como DADO, não como código (D3.2).
#
# Oito chaves, uma por linha da tabela, NA MESMA ORDEM. Toda policy de recurso
# decide invocando `allows?` com uma destas actions; nenhuma policy compara
# papel diretamente (o cop do grupo 6 reprova `role ==` fora deste arquivo).
# O spec `spec/policies/permission_matrix_spec.rb` reafirma as 8 linhas
# literalmente — mudar a matriz exige mudar dois lugares de propósito.
module PermissionMatrix
  ACTIONS = {
    read_workspace:         %i[owner edit view],
    manage_commissioning:   %i[owner edit],
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
