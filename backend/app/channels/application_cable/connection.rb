# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # Ponto de estrangulamento do Cable: nenhum canal é instanciado sem passar
    # por aqui, então um canal futuro não pode esquecer de verificar identidade
    # (só pode esquecer de verificar autorização, que é problema da D3/D6).
    def find_verified_user
      token = request.params[:token]
      reject_unauthorized_connection if token.blank?

      user = begin
        payload = nil
        payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
        payload ||= Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
        uid = payload['sub'] || payload['user_id']
        User.find_by(id: uid)
      rescue StandardError
        nil
      end

      reject_unauthorized_connection if user.nil?
      user
    end
  end
end
