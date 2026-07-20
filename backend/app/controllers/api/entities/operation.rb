# frozen_string_literal: true

module Api
  module Entities
    class Operation < Grape::Entity
      expose :id
      expose :smart_id
      expose :key
      expose :title
      expose :description
      expose :keywords
      expose :active
      expose :created_at
      expose :updated_at

      # Campos calculados
      expose :keywords_count do |operation|
        operation.keywords_array.size
      end

      # Contagem de leads associados
      expose :leads_count do |operation|
        operation.respond_to?(:leads_count) ? operation.leads_count : 0
      end
    end
  end
end
