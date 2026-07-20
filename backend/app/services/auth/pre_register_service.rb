# frozen_string_literal: true

module Auth
  class PreRegisterService
    include ApiResponseHandler

    def initialize(identifier:, method:, ip_address:, user_agent:)
      @identifier = identifier.to_s.strip
      @method = method.to_s.downcase
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      normalized = LoginCode.normalize_destination_value(@identifier)
      if @method == 'email' && !normalized.match?(URI::MailTo::EMAIL_REGEXP)
        return validation_error_response('Email inválido')
      end

      if @method == 'whatsapp'
        digits = normalized.gsub(/[^0-9]/, '')
        return validation_error_response('WhatsApp inválido (formato internacional)') unless digits.length.between?(10,
                                                                                                                    15)
      end

      user = if @method == 'email'
               User.find_by(email: normalized)
             else
               User.by_phone(normalized).first
             end

      last_code = LoginCode.by_destination(normalized).by_method(@method).recent.first
      if last_code && !last_code.can_resend?
        return rate_limit_response("Aguarde #{last_code.time_until_resend} segundos para reenviar")
      end

      code_record = LoginCode.generate_for(normalized, @method, user)

      if @method == 'email'
        ::Auth::EmailService.new(user: user, code: code_record.code).send_magic_login_code
      else
        begin
          number = normalized.gsub(/[^0-9]/, '')
          app = ENV.fetch('APP_NAME', 'robotrack')
          message_text = "🔒 *#{app}* — seu código de acesso: *#{code_record.code}*\n\n⏰ Expira em 5 minutos.\n⚠️ Não compartilhe este código com ninguém."
          EvolutionConnection.send_message({ number: number, text: message_text })
        rescue StandardError
          Rails.logger.warn('[PreRegisterService] Falha ao enviar WhatsApp via Evolution')
        end
      end

      payload = {
        success: true,
        message: 'Código enviado',
        method: @method,
        identifier: normalized,
        is_new_user: user.nil?,
        requires_completion: user.nil?
      }
      payload[:code] = code_record.code if Rails.env.development?
      success_response(payload)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def rate_limit_response(message)
      { status: 429, error: 'rate_limit_exceeded', details: { message: message } }
    end
  end
end
