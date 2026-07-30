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
          route_setting :policy, access: :authenticated
          get do
            status 200
            { data: { user: Api::Entities::User.represent(current_user) } }
          end

          # internationalization G6 (D-I6) — atualiza a preferência de idioma da
          # PRÓPRIA conta. O sujeito é o token (`current_user`); NENHUM parâmetro troca
          # de quem é o locale — logo, ninguém altera o locale de outra pessoa. O CHECK
          # do banco é a garantia final do par de valores.
          route_setting :policy, access: :authenticated
          params do
            requires :locale, type: String, values: %w[pt-BR en]
          end
          patch do
            # `update_column`: grava SÓ o locale, sem disparar as validações legadas do
            # model User (telefone/cpf/cep herdados do template, que reprovariam um
            # update parcial). O valor já é garantido pelo `values:` do Grape e pelo
            # CHECK do banco — validar de novo aqui só traria o campo minado do legado.
            current_user.update_column(:locale, params[:locale])
            status 200
            { data: { user: Api::Entities::User.represent(current_user) } }
          end
        end
      end
    end
  end
end
