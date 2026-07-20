# frozen_string_literal: true

class PermissionConflict < ApplicationRecord
  belongs_to :permission
  belongs_to :conflicts_with, class_name: 'Permission'

  validates :permission_id, uniqueness: { scope: :conflicts_with_id }
end
