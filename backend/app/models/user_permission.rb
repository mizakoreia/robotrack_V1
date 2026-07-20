# frozen_string_literal: true

class UserPermission < ApplicationRecord
  belongs_to :user
  belongs_to :permission

  validates :source, presence: true
  validates :granted_at, presence: true

  scope :active, -> { where(revoked_at: nil) }
end
