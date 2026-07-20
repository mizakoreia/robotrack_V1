# frozen_string_literal: true

module Api
  module Entities
    class AuthResponse < Grape::Entity
      expose :user, using: Api::Entities::User
      expose :token
      expose :refresh_token
    end
  end
end
