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
      # internationalization G6 — a preferência de idioma da conta viaja no payload de
      # login/me, para o cliente hidratar o `rt-lang` já na entrada (segue a pessoa
      # entre dispositivos).
      expose :locale
    end
  end
end
