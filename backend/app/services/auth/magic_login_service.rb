# frozen_string_literal: true

module Auth
  class MagicLoginService
    include ApiResponseHandler

    def initialize(identifier:, method:, ip_address:, user_agent:)
      @identifier = identifier
      @method = method
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      normalized_identifier = LoginCode.normalize_destination_value(@identifier)
      return validation_error_response('Identificador inválido') unless valid_identifier?(normalized_identifier)

      user = find_user(normalized_identifier, @method)
      return validation_error_response('Usuário não encontrado') unless user

      return rate_limited_response unless can_request_code?(user, normalized_identifier)

      Rails.logger.info("[MagicLoginService] Solicitação de código para #{masked_identifier(normalized_identifier)} via #{@method}")
      create_login_attempt(success: false, user: user)

      code = generate_login_code

      LoginCode.create!(
        destination: normalized_identifier,
        method: @method,
        code: code,
        expires_at: 5.minutes.from_now,
        attempts: 0,
        user: user
      )

      send_code(user, normalized_identifier, code)
      Rails.logger.info("[MagicLoginService] Código enviado com sucesso para #{masked_identifier(normalized_identifier)} via #{@method}")

      update_last_attempt(success: true)

      response_msg = {
        message: "Código enviado para #{@method == 'email' ? 'email' : 'WhatsApp'}",
        destination: normalized_identifier,
        method: @method
      }

      response_msg[:code] = code if Rails.env.development?

      success_response(response_msg)
    rescue EvolutionConnection::InvalidResponseError => e
      update_last_attempt(success: false)
      internal_error_response("Erro na Evolution API: #{e.error}")
    rescue EvolutionConnection::TimeoutError, EvolutionConnection::ConnectionError => e
      update_last_attempt(success: false)
      internal_error_response(e.message)
    rescue ActiveRecord::RecordInvalid => e
      update_last_attempt(success: false)
      validation_error_response(e.message)
    rescue StandardError => e
      update_last_attempt(success: false)
      internal_error_response(e.message)
    end

    private

    # Normalização realizada via LoginCode.normalize_destination_value

    def generate_login_code
      rand(100_000..999_999).to_s
    end

    def create_login_attempt(success:, user: nil)
      LoginAttempt.create!(
        identifier: @identifier,
        method: @method,
        ip_address: @ip_address,
        user_agent: @user_agent,
        success: success,
        user: user
      )
    end

    def update_last_attempt(success:)
      last_attempt = LoginAttempt.where(
        identifier: @identifier,
        method: @method,
        ip_address: @ip_address
      ).last

      last_attempt&.update!(success: success)
    end

    def send_code(user, destination, code)
      if @method == 'email'
        Auth::EmailService.new(user: user, code: code).send_magic_login_code
      else
        number = destination.gsub(/[^0-9]/, '')
        message_text = "🔒 *#{app_name}* — seu código de acesso: *#{code}*\n\n⏰ Expira em 5 minutos.\n⚠️ Não compartilhe este código com ninguém."
        EvolutionConnection.send_message({ number: number, text: message_text })
      end
    end

    def find_user(identifier, method)
      if method == 'email'
        User.find_by(email: identifier)
      else
        User.by_phone(identifier).first
      end
    end

    def valid_identifier?(identifier)
      if @method == 'email'
        identifier.match?(URI::MailTo::EMAIL_REGEXP)
      else
        digits = identifier.gsub(/[^0-9]/, '')
        digits.length.between?(10, 15)
      end
    end

    def can_request_code?(user, identifier)
      return false if LoginAttempt.suspicious_activity?(identifier, @ip_address)
      return false if LoginAttempt.brute_force_detected?(identifier, @ip_address)

      user.can_request_new_code?
    end

    def rate_limited_response
      validation_error_response('Limite de solicitação atingido. Aguarde antes de tentar novamente')
    end

    def masked_identifier(identifier)
      if @method == 'email'
        parts = identifier.split('@')
        return identifier if parts.length != 2

        local = parts[0]
        domain = parts[1]
        masked_local = local.length <= 3 ? "#{local[0]}***" : "#{local[0..2]}***"
        "#{masked_local}@#{domain}"
      else
        digits = identifier.gsub(/[^0-9]/, '')
        return '***' if digits.length < 4

        "***#{digits[-4..]}"
      end
    end

    def app_name
      ENV.fetch('APP_NAME', 'robotrack')
    end
  end
end
