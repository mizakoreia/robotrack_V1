# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      # Sessão por senha (identity-and-auth 4.1):
      #   POST   /auth/v1/session        — login (público)
      #   DELETE /auth/v1/session        — logout (exige token; revoga o jti)
      #   POST   /auth/v1/session/renew  — renovação (exige token; rotaciona o jti)
      #
      # A allowlist ANCORADA de api/root.rb torna público apenas `^/auth/v1/session/?$`
      # — `session/renew` fica protegido (D4.8). `DELETE` também exige token: o
      # servidor precisa dele para saber qual `jti` revogar.
      class Session < Grape::API
        namespace :session do
          desc 'Login por e-mail e senha' do
            success [code: 200, message: 'Autenticado']
            failure [{ code: 401, message: 'Credenciais inválidas' }, { code: 429, message: 'Muitas tentativas' }]
          end
          params do
            requires :email, type: String
            requires :password, type: String
            optional :remember_me, type: Boolean, default: false
          end
          post do
            result = ::Auth::SessionService.login(
              email: params[:email],
              password: params[:password],
              remember_me: params[:remember_me]
            )
            render_auth_result(result)
          end

          desc 'Logout — revoga o token apresentado' do
            success [code: 204, message: 'Sessão encerrada']
            failure [{ code: 401, message: 'Não autenticado' }]
          end
          delete do
            # api/root.rb já autenticou (rota protegida); revogamos o próprio token.
            render_auth_result(::Auth::SessionService.logout(token: bearer_token))
          end

          namespace :renew do
            desc 'Renovação com rotação de jti e teto absoluto' do
              success [code: 200, message: 'Renovado']
              failure [{ code: 401, message: 'Sessão expirada' }]
            end
            post do
              render_auth_result(::Auth::SessionService.renew(token: bearer_token))
            end
          end
        end
      end
    end
  end
end
