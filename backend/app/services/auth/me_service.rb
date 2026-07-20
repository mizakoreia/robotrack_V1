# frozen_string_literal: true

module Auth
  class MeService
    include ApiResponseHandler

    def initialize(user)
      @user = user
    end

    def show
      return unauthorized_response('Não autenticado') unless @user

      success_response(Api::Entities::User.represent(@user), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def update(params, csrf_token)
      return unauthorized_response('Não autenticado') unless @user

      validator = Auth::CsrfService.new(@user)
      return forbidden_response('CSRF inválido') unless validator.valid?(csrf_token)

      attrs = params.slice(:email, :phone, :name, :avatar_url, :cpf_cnpj, :cep, :street, :number, :complement,
                           :district, :city, :state).compact
      return validation_error_response('Nenhum campo para atualizar') if attrs.empty?

      if @user.update(attrs)
        success_response(Api::Entities::User.represent(@user), 200)
      else
        validation_error_response('Dados inválidos', details: @user.errors.full_messages)
      end
    rescue StandardError => e
      internal_error_response(e.message)
    end
  end
end
