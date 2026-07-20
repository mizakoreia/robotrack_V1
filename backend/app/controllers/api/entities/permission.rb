# frozen_string_literal: true

module Api
  module Entities
    class Permission < Grape::Entity
      expose :id
      expose :key
      expose :title
      expose :description
    end
  end
end
