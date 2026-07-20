# frozen_string_literal: true

module Api
  module Entities
    class LoginCodeResponse < Grape::Entity
      expose :success
      expose :message
      # expose :code, if: Rails.env.development?
    end
  end
end
