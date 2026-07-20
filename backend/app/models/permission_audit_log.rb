# frozen_string_literal: true

class PermissionAuditLog < ApplicationRecord
  belongs_to :user
  belongs_to :plan, optional: true
  belongs_to :actor, polymorphic: true, optional: true

  validates :change_type, presence: true
end
