# frozen_string_literal: true

module Api
  module Auth
    module V1
      class Me < Grape::API
        before { authenticate_user! }
        namespace :me do
          get do
            service = ::Auth::MeService.new(current_user)
            process_service_response(service.show)
          end

          params do
            optional :email, type: String
            optional :phone, type: String
            optional :name, type: String
            optional :avatar_url, type: String
            optional :cpf_cnpj, type: String
            optional :cep, type: String
            optional :street, type: String
            optional :number, type: String
            optional :complement, type: String
            optional :district, type: String
            optional :city, type: String
            optional :state, type: String
          end
          patch do
            csrf_header = headers['X-CSRF-Token'] || headers['HTTP_X_CSRF_TOKEN']
            error!({ error: 'csrf_required', message: 'CSRF token ausente' }, 403) unless csrf_header.present?
            service = ::Auth::MeService.new(current_user)
            process_service_response(service.update(params, csrf_header))
          end
        end
      end
    end
  end
end
