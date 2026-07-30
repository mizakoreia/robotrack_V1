# frozen_string_literal: true

# notification-preferences D-P6. Preferência de notificação é CONFIGURAÇÃO PESSOAL,
# self-scoped: qualquer membro (owner/edit/view) gere a PRÓPRIA — mesma natureza do
# `mark_notification_read` (L6), não autoria de domínio. A escrita é sempre para a
# pessoa corrente (o endpoint não aceita `person_id` de terceiro); `mutate?` mantém
# a checagem de posse por simetria com `NotificationPolicy#mark_read?` — nem o dono
# edita a preferência alheia. Consulta a matriz PRIMEIRO (fail-closed p/ papel nulo,
# como o route-sweep exige).
class NotificationSubscriptionPolicy < BasePolicy
  permits index?: :manage_own_subscription

  class << self
    def mutate?(context, subscription = nil)
      return false unless PermissionMatrix.allows?(:manage_own_subscription, context.role)
      return false if subscription && context.person.nil?

      subscription.nil? || subscription.person_id == context.person.id
    end
  end
end
