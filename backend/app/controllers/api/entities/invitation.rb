# frozen_string_literal: true

module Api
  module Entities
    # code-only-invites §"A tela mostra só o código".
    #
    # NÃO sai `invite_url` nem nenhum campo de token: o link de convite foi
    # removido do produto (o único caminho é o código). O `token` do banco fica
    # dormente e nunca é serializado — expô-lo espalharia uma credencial dormente
    # por logs, analytics e props de componente sem nenhum consumidor.
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

      # invite-by-code: o código em CLARO sai UMA única vez — na criação, quando o
      # `short_code` transiente está preenchido —, formatado `XXXX-XXXX`. Depois
      # disso a listagem recarrega do banco (sem o claro) e este bloco não expõe
      # nada. O `code_hash` NUNCA é serializado.
      expose(:short_code, if: ->(inv, _o) { inv.short_code.present? }) do |inv|
        inv.short_code.gsub(/(.{4})(.{4})/, '\1-\2')
      end
      # Estado do código na listagem de pendentes (ativo/expirado/travado/usado ou
      # nil quando o convite é só-link). Nunca o hash, nunca o claro.
      expose(:code_status) { |inv| inv.code_status }
      expose :code_expires_at
    end
  end
end
