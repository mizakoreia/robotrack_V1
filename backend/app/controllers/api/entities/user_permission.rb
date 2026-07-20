# frozen_string_literal: true

module Api
  module Entities
    class UserPermission < Grape::Entity
      expose :id
      expose :source
      expose :granted_at
      expose :revoked_at
      expose :permission, as: :permission do |up|
        Api::Entities::Permission.represent(up.permission)
      end
    end
  end
end
