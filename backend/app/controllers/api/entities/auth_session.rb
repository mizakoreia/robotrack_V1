# frozen_string_literal: true

module Api
  module Entities
    class AuthSession < Grape::Entity
      expose :success
      expose :message
      expose :user, using: Api::Entities::User, safe: true
      expose :access_token do |obj|
        obj.respond_to?(:[]) ? (obj[:access_token] || obj[:token]) : (obj.try(:access_token) || obj.try(:token))
      end
      expose :token
      expose :refresh_token
      expose :requires_completion, if: ->(obj, _opts) { obj.respond_to?(:[]) && obj.key?(:requires_completion) }
      expose :is_new_user, if: ->(obj, _opts) { obj.respond_to?(:[]) && obj.key?(:is_new_user) }
    end
  end
end
