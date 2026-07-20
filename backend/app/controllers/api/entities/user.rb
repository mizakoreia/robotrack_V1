# frozen_string_literal: true

module Api
  module Entities
    # Entidade pública de usuário (identity-and-auth 4.1). Expõe SÓ o necessário
    # para identificar quem está autenticado. A entidade herdada do template
    # expunha dezenas de colunas, incluindo `credit_card_*` e `cpf_cnpj` — dado
    # que não pode sair numa resposta de `GET /auth/v1/me`.
    class User < Grape::Entity
      expose :id
      expose :name
      expose :email
      expose :avatar_url
    end
  end
end
