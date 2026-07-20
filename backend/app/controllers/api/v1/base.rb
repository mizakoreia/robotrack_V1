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

      namespace :auth do
        mount Api::Auth::V1::Registration
      end

      namespace :leads do
        mount Api::V1::Leads
      end

      namespace :operations do
        mount Api::V1::Operations
      end

      namespace :lead_messages do
        mount Api::V1::LeadMessages
      end



      namespace :permissions do
        mount Api::V1::Permissions
      end

      # Tratamento de erro é único e vive em Api::Root.
    end
  end
end
