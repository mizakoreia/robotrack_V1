# frozen_string_literal: true

module Auth
  class CompleteRegistrationService
    include ApiResponseHandler

    def initialize(identifier:, method:, code:, name:, email: nil, whatsapp: nil)
      @identifier = identifier.to_s.strip
      @method = method.to_s.downcase
      @code = code.to_s.strip
      @name = name.to_s.strip
      @email = email
      @whatsapp = whatsapp
    end

    def execute!
      return validation_error_response('Nome deve ter ao menos 3 caracteres') if @name.length < 3

      normalized = LoginCode.normalize_destination_value(@identifier)
      login_code = LoginCode.verify_code(normalized, @method, @code)
      return unauthorized_response('Código inválido ou expirado') unless login_code

      user = login_code.user
      client_type = UserType.client
      if user.nil?
        attrs = {
          name: @name,
          user_type: client_type,
          provider: @method
        }
        if @method == 'email'
          attrs[:email] = normalized
          attrs[:phone] = @whatsapp.present? ? User.normalize_phone_number(@whatsapp) : nil
        else
          attrs[:phone] = User.normalize_phone_number(normalized)
          attrs[:email] = @email.presence
        end
        user = User.create!(attrs)
      else
        user.update!(
          name: @name,
          email: @method == 'whatsapp' ? (@email.presence || user.email) : normalized,
          phone: @method == 'email' ? (User.normalize_phone_number(@whatsapp).presence || user.phone) : User.normalize_phone_number(normalized),
          user_type: client_type,
          provider: @method
        )
      end

      login_code.use!

      tokens = ::Auth::TokenService.new(user).generate_tokens
      success_response(Api::Entities::AuthSession.represent({
                                                              success: true,
                                                              message: 'Cadastro concluído',
                                                              user: user,
                                                              access_token: tokens[:token],
                                                              token: tokens[:token],
                                                              refresh_token: tokens[:refresh_token],
                                                              is_new_user: true
                                                            }))
    rescue StandardError => e
      internal_error_response(e.message)
    end
  end
end
