# frozen_string_literal: true

module Api
  module Auth
    module V1
      # GET /auth/v1/me — identidade do usuário autenticado (identity-and-auth
      # 4.1). Protegido: api/root.rb autentica antes de chegar aqui; o token
      # identifica o sujeito e nenhum parâmetro consegue trocá-lo.
      class Me < Grape::API
        before { authenticate_user! }

        namespace :me do
          get do
            status 200
            { data: { user: Api::Entities::User.represent(current_user) } }
          end
        end
      end
    end
  end
end
