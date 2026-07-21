# frozen_string_literal: true

module Api
  module Entities
    # workspace-invitations §"Cópia do link de convite" (tarefa 2.4).
    #
    # NÃO existe campo `token` solto: o token só sai embutido no `invite_url`, que
    # é o que o dono precisa (copiar o link, inclusive relendo a lista de
    # pendentes depois de fechar o diálogo). Um campo `token` cru convidaria a UI
    # a montar a URL por conta própria e a espalhar a credencial por logs,
    # analytics e props de componente.
    #
    # `created_by_person_id` e `workspace_id` não saem: o cliente já sabe em que
    # workspace está e não tem o que fazer com o id da pessoa criadora.
    class Invitation < Grape::Entity
      expose :id
      expose :email
      expose :role
      expose :status
      expose :expires_at
      expose :created_at
      expose(:invite_url) { |invitation| ::AppUrl.invite_url(invitation.token) }
    end
  end
end
