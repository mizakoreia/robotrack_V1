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

      namespace :analytics do
        mount Api::V1::Analytics
      end

      # Tratamento de erros específico, se necessário
      rescue_from :all do |e|
        unless (e.is_a? Grape::Exceptions::ValidationErrors) ||
               (e.is_a? Grape::Exceptions::MethodNotAllowed) ||
               e.message.include?('Mysql2::Error') ||
               (e.is_a? PG::Error)

          env = {}
          env['exception_notifier.exception_data'] = {
            api: 'API ERROR - POLEMK WHATS',
            message: e.message,
            user: 'No User.',
            environment: Rails.env
          }
        end

        # Log de erro
        error_backtrace = "ERROR - API POLEMK: #{e.message} <br/> \n BACKTRACE: #{e.backtrace.join "\n"}"
        Rails.logger.warn error_backtrace
        error!(error_backtrace)
      end
    end
  end
end
