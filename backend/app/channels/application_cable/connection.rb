# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      user = find_verified_user
      self.current_user = user if user.present?
    end

    private

    def find_verified_user
      token = request.params[:token]
      return nil unless token.present?

      begin
        payload = nil
        payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
        payload ||= Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
        uid = payload['sub'] || payload['user_id']
        User.find_by(id: uid)
      rescue StandardError
        nil
      end
    end

    def allow_public_checkout_subscription?
      any_id = request.params[:purchase_id]
      return false unless any_id.present?
      Purchase.by_any_id(any_id).present?
    end

    def decode_user_id(token)
      payload = Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
      payload['sub'] || payload['user_id']
    end
  end
end
