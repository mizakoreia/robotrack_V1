# frozen_string_literal: true

# §4.1 linhas 1, 5 e 6, inv. 4 (D3.7): qualquer membro marca como lida a
# notificação CUJO DESTINATÁRIO É ELE PRÓPRIO — endurecimento sobre a rule
# legada L61, que deixava marcar a alheia (divergência D-A). A restrição de
# colunas (só `read`/`read_at` mudam) é trigger de banco, da tarefa 3.3.
class NotificationPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :create_log

  class << self
    def mark_read?(context, notification = nil)
      return false unless PermissionMatrix.allows?(:mark_notification_read, context.role)
      return false if notification && context.person.nil?

      notification.nil? || notification.recipient_person_id == context.person.id
    end
  end
end
