# frozen_string_literal: true

require 'grape'

module Api
  module Auth
    module V1
      # POST /auth/v1/registration — cadastro por e-mail e senha (identity-and-auth
      # 4.1). Público (allowlist ancorada em api/root.rb).
      class Registration < Grape::API
        namespace :registration do
          desc 'Cadastro por e-mail e senha' do
            success [code: 201, message: 'Cadastrado']
            failure [
              { code: 409, message: 'E-mail já cadastrado' },
              { code: 422, message: 'Dados inválidos' }
            ]
          end
          params do
            requires :name, type: String, desc: 'Nome de exibição'
            requires :email, type: String, desc: 'E-mail'
            requires :password, type: String, desc: 'Senha (mínimo 6)'
            optional :remember_me, type: Boolean, default: false, desc: 'Manter conectado'
          end
          post do
            result = ::Auth::RegistrationService.call(
              name: params[:name],
              email: params[:email],
              password: params[:password],
              remember_me: params[:remember_me]
            )
            render_auth_result(result)
          end
        end
      end
    end
  end
end
