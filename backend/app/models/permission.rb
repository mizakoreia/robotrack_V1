# frozen_string_literal: true

class Permission < ApplicationRecord
  has_many :plan_feature_permissions, dependent: :destroy
  has_many :plan_features, through: :plan_feature_permissions
  has_many :user_permissions, dependent: :destroy

  validates :key, presence: true, uniqueness: true
  validates :title, presence: true

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:sort_order, :created_at) }
end
