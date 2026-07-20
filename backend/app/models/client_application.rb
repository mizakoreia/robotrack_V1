# frozen_string_literal: true

class ClientApplication < ApplicationRecord
  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  scope :active, -> { where(active: true) }
end
