module Api
  module Entities
    class Sale < Grape::Entity
      expose :id
      expose :customer_name
      expose :customer_email
      expose :amount
      expose :currency
      expose :status
      expose :type
      expose :method
      expose :subscription_id
      expose :external_id
      expose :created_at
    end
  end
end

