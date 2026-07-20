# frozen_string_literal: true

module Auth
  class VerifyCodeService
    include ApiResponseHandler

    def initialize(identifier:, method:, code:)
      @identifier = identifier.to_s.strip
      @method = method.to_s.downcase
      @code = code.to_s.strip
    end

    def execute!
      normalized = LoginCode.normalize_destination_value(@identifier)
      login_code = LoginCode.verify_code(normalized, @method, @code)
      return unauthorized_response('Código inválido ou expirado') unless login_code

      user = login_code.user
      if user.nil?
        return success_response({
                                  success: true,
                                  message: 'Código válido',
                                  time_remaining: login_code.time_remaining,
                                  requires_completion: true
                                })
      end
      created_recently = user.created_at.present? && login_code.created_at.present? &&
                         user.login_count.to_i.zero? && user.last_login_at.nil? &&
                         (user.created_at >= (login_code.created_at - 2.minutes))
      unless created_recently
        tokens = ::Auth::TokenService.new(user).generate_tokens
        user.update!(
          last_login_at: Time.current,
          login_count: user.login_count + 1
        )
        login_code.use!
        return success_response(Api::Entities::AuthSession.represent({
                                                                       success: true,
                                                                       message: 'Login realizado com sucesso',
                                                                       user: user,
                                                                       access_token: tokens[:token],
                                                                       token: tokens[:token],
                                                                       refresh_token: tokens[:refresh_token],
                                                                       requires_completion: false
                                                                     }))
      end
      success_response({
                         success: true,
                         message: 'Código válido',
                         time_remaining: login_code.time_remaining,
                         requires_completion: true
                       })
    rescue StandardError => e
      internal_error_response(e.message)
    end
  end
end
