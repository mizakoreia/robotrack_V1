# frozen_string_literal: true

module Auth
  class SessionsService
    include ApiResponseHandler

    def self.status(params)
      new.status(params)
    end

    def self.refresh(params)
      new.refresh(params)
    end

    def self.logout(params)
      new.logout(params)
    end

    def status(params)
      token = params[:token] || extract_token_from_header(params)
      return success_response({ valid: false }) if token.blank?

      begin
        payload = Auth::TokenService.new(nil).decode_token(token)
        unless payload['type'].to_s == 'user' || payload['sub'].present?
          return success_response({ valid: false })
        end

        user = User.find_by(id: payload['sub'])
        return success_response({ valid: false }) unless user

        success_response({
                           valid: true,
                           user: Api::Entities::User.represent(user),
                           expires_at: Time.at(payload['exp'])
                         })
      rescue JWT::ExpiredSignature
        success_response({ valid: false })
      rescue JWT::DecodeError
        success_response({ valid: false })
      end
    end

    def refresh(params)
      refresh_token = params[:refresh_token]
      return unauthorized_response('Refresh token não fornecido') if refresh_token.blank?

      begin
        payload = Auth::TokenService.new(nil).decode_token(refresh_token)
        return unauthorized_response('Tipo de token inválido') unless payload['type'].to_s == 'refresh'

        user = User.find_by(id: payload['sub'])
        return unauthorized_response('Usuário não encontrado') unless user

        tokens = Auth::TokenService.new(user).generate_tokens
        session_payload = {
          user: user,
          token: tokens[:token],
          refresh_token: tokens[:refresh_token]
        }
        success_response(Api::Entities::AuthSession.represent(session_payload))
      rescue JWT::ExpiredSignature
        unauthorized_response('Refresh token expirado')
      rescue JWT::DecodeError
        unauthorized_response('Refresh token inválido')
      end
    end

    def logout(params)
      token = params[:token] || extract_token_from_header(params)
      return validation_error_response('Token não fornecido') if token.blank?

      begin
        payload = Auth::TokenService.new(nil).decode_token(token, verify_exp: false)
        if ActiveRecord::Base.connection.table_exists?('jwt_denylist')
          exp = Time.at(payload['exp'] || Time.current.to_i + 60)
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.send(:sanitize_sql_array, [
                                      'INSERT INTO jwt_denylist (jti, exp, created_at, updated_at) VALUES (?, ?, NOW(), NOW())',
                                      payload['jti'] || SecureRandom.uuid,
                                      exp
                                    ])
          )
        end
      rescue StandardError
      end

      success_response({ message: 'Logout realizado com sucesso' })
    end

    private

    def extract_token_from_header(params)
      # Extrair token do header Authorization
      auth_header = params[:authorization] || params[:http_authorization]
      return nil if auth_header.blank?

      auth_header.split(' ').last
    end
  end
end
