# frozen_string_literal: true

module Api
  module Entities
    class PermissionAuditLog < Grape::Entity
      expose :id
      expose :user_id
      expose :plan_id
      expose :change_type
      expose :permissions_added
      expose :permissions_removed
      expose :source_event
      expose :reason
      expose :metadata
      expose :created_at
    end
  end
end
