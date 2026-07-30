# frozen_string_literal: true

module Api
  module Entities
    # notification-preferences D-P6. Preferência da própria pessoa sobre um alvo da
    # hierarquia. `scope_type`/`scope_id` colapsam as três colunas para o cliente
    # hidratar os sinos seguir/silenciar.
    class NotificationSubscription < Grape::Entity
      expose :id
      expose :scope_type
      expose :scope_id
      expose :state
      expose :created_at
      expose :updated_at
    end
  end
end
