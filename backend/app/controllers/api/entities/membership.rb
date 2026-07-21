# frozen_string_literal: true

module Api
  module Entities
    # team-access-management §"Painel de equipe" (tarefa 4.4).
    #
    # `role` é rótulo derivado no servidor, como em toda a superfície desde a
    # Onda 1 — o cliente nunca o envia de volta para decidir nada. `is_owner`
    # existe para a UI marcar a linha imutável; a imutabilidade em si é do
    # servidor (`owner_is_immutable`/`cannot_remove_owner`).
    class Membership < Grape::Entity
      expose :id
      expose :person_id
      expose :name
      expose :email
      expose :role
      expose :is_owner
      expose :invitation_id
    end
  end
end
