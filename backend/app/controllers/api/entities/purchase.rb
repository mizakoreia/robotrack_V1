# frozen_string_literal: true

module Api
  module Entities
    class Purchase < Grape::Entity
      expose :id
      expose :identifier
      expose :status
      expose :billing_type
      expose :cycle
      expose :value
      expose :installment_count
      expose :plan_name
      expose :asaas_id
      expose :customer_id
    end
  end
end
