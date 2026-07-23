# frozen_string_literal: true

# in-app-notifications (D-N2). A coluna `type` é o ENUM de negócio
# (assign/progress/done), NÃO o discriminador de STI do Rails — daí
# `inheritance_column = nil`. As invariantes 4 e 8 são de banco (triggers/CHECK).
class Notification < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :workspace
  belongs_to :recipient, class_name: 'Person', foreign_key: :recipient_person_id, inverse_of: false
  belongs_to :actor, class_name: 'Person', foreign_key: :actor_person_id, inverse_of: false

  TYPES = %w[assign progress done].freeze
end
