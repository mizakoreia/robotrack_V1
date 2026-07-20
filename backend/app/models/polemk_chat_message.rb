# frozen_string_literal: true

class PolemkChatMessage < ApplicationRecord
  belongs_to :polemk_instance
  belongs_to :polemk_instance_group

  validates :full_number, presence: true
  validates :message, presence: true
  validates :ip_address, presence: true
  validates :user_agent, presence: true
end
