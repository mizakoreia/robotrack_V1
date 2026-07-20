# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      class Base < Grape::API
        format :json
        prefix :auth
        version 'v1', using: :path

        helpers do
          def authenticate_user!
            user = env['api.current_user']
            error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) unless user
            @current_user = user
          end

          attr_reader :current_user

          # Bearer do header Authorization, ou nil.
          def bearer_token
            raw = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
            return nil if raw.blank?

            scheme, token = raw.to_s.split(' ', 2)
            scheme == 'Bearer' ? token : nil
          end

          # Envelope único das respostas de auth (identity-and-auth): sucesso em
          # `data`, erro em `error`/`errors`, e o token também no header
          # `Authorization` (spec §"Cadastro"/§"Login"). 204 sem corpo.
          def render_auth_result(result)
            if result[:ok]
              header 'Authorization', "Bearer #{result[:token]}" if result[:token]
              status result[:status]
              if result[:status] == 204
                body false
              else
                { data: { access_token: result[:token], user: Api::Entities::User.represent(result[:user]) } }
              end
            else
              status result[:status]
              result[:errors] ? { errors: result[:errors] } : { error: result[:error] }
            end
          end
        end

        # Endpoints de autenticação.
        mount Api::Auth::V1::Oauth        # legado (google_url/callback) — sai em G3
        mount Api::Auth::V1::Registration
        mount Api::Auth::V1::Session
        mount Api::Auth::V1::Me

        # Tratamento de erro é único e vive em Api::Root.
      end
    end
  end
end
