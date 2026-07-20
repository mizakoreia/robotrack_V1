# frozen_string_literal: true

module Api
  module Entities
    # workspace-core §"Índice do usuário". `role` é RÓTULO DE UI derivado ao vivo
    # no servidor (owner de owner_user_id, senão a membership) — nunca lido do
    # cliente para decidir nada (D9 / §4.1 inv. 2).
    class Workspace < Grape::Entity
      expose :id
      expose :name
      expose :role
    end
  end
end
