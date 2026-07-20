# frozen_string_literal: true

module Api
  module Entities
    class PolemkWebhook < Grape::Entity
      expose :id
      expose :polemk_instance_id
      expose :url
      expose :enabled
      expose :webhook_by_events
      expose :webhook_base_64
      expose :event
      expose :raw_response
      expose :created_at
      expose :updated_at
    end
  end
end
