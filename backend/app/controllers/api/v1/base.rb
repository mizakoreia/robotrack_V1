# frozen_string_literal: true

module Api
  module V1
    class Base < Grape::API
      format :json
      version 'v1', using: :path
      prefix :api

      helpers Api::V1::ControllerHelpers

      namespace :users do
        mount Api::V1::Users
      end

      namespace :uploads do
        mount Api::V1::Uploads
      end

      mount Api::V1::Countries

      mount Api::V1::Downloads

      # Tratamento de erro é único e vive em Api::Root.
    end
  end
end
