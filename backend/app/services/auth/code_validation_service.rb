# frozen_string_literal: true

module Auth
  class CodeValidationService
    include ApiResponseHandler

    def initialize(identifier:, code:, method:, ip_address:, user_agent:)
      @identifier = identifier
      @code = code
      @method = method
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def execute!
      normalized_identifier = LoginCode.normalize_destination_value(@identifier)

      # Buscar código válido
      login_code = LoginCode.where(
        destination: normalized_identifier,
        method: @method,
        code: @code
      ).where('expires_at > ?', Time.current).where(used_at: nil).order(created_at: :desc).first

      unless login_code
        create_login_attempt(success: false)
        return unauthorized_response('Código inválido ou expirado')
      end

      # Verificar limite de tentativas
      if login_code.attempts >= 5
        login_code.destroy!
        return unauthorized_response('Código bloqueado por muitas tentativas')
      end

      # Incrementar tentativas
      login_code.increment!(:attempts)

      # Verificar se código está correto
      unless login_code.code == @code
        create_login_attempt(success: false)
        return unauthorized_response('Código inválido')
      end

      user = login_code.user
      unless user
        create_login_attempt(success: false)
        return unauthorized_response('Usuário não encontrado. Conclua o cadastro para continuar')
      end

      # Gerar tokens JWT via Warden JWTAuth se disponível
      token_service = Auth::TokenService.new(user)
      tokens = token_service.generate_tokens

      # Atualizar último login
      user.update!(
        last_login_at: Time.current,
        login_count: user.login_count + 1
      )

      # Marcar código como usado
      login_code.update!(used_at: Time.current)

      # Criar registro de sucesso
      create_login_attempt(success: true)

      session_payload = {
        success: true,
        message: 'Login realizado com sucesso',
        user: user,
        access_token: tokens[:token],
        token: tokens[:token],
        refresh_token: tokens[:refresh_token]
      }
      success_response(Api::Entities::AuthSession.represent(session_payload))
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    # Normalização centralizada via LoginCode.normalize_destination_value

    def find_or_create_user(identifier, method)
      if method == 'email'
        User.find_or_create_by!(email: identifier) do |user|
          user.name = identifier.split('@').first
          user.phone = ''
        end
      else
        normalized = User.normalize_phone_number(identifier)
        User.find_or_create_by!(phone: normalized) do |user|
          user.name = 'Usuário WhatsApp'
          user.email = ''
        end
      end
    end

    def create_login_attempt(success:)
      LoginAttempt.create!(
        identifier: @identifier,
        method: @method,
        ip_address: @ip_address,
        user_agent: @user_agent,
        success: success
      )
    end
  end
end
