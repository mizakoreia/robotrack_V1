# frozen_string_literal: true

module Api
  module Entities
    class User < Grape::Entity
      expose :id
      expose :email
      expose :phone
      expose :name
      expose :avatar_url
      expose :cpf_cnpj, if: ->(user, _opts) { user.respond_to?(:cpf_cnpj) }
      expose :cep, if: ->(user, _opts) { user.respond_to?(:cep) }
      expose :street, if: ->(user, _opts) { user.respond_to?(:street) }
      expose :number, if: ->(user, _opts) { user.respond_to?(:number) }
      expose :complement, if: ->(user, _opts) { user.respond_to?(:complement) }
      expose :district, if: ->(user, _opts) { user.respond_to?(:district) }
      expose :city, if: ->(user, _opts) { user.respond_to?(:city) }
      expose :state, if: ->(user, _opts) { user.respond_to?(:state) }
      expose :user_type_id
      expose :is_og do |user, _opts|
        user.og?
      end
      expose :user_type, as: :user_type do |user|
        user.user_type&.display_name
      end
      expose :last_login_at
      expose :login_count
      expose :created_at
      expose :updated_at
      expose :biography_html, if: lambda { |user, _opts|
        user.respond_to?(:biography) && begin
          ActiveRecord::Base.connection.data_source_exists?('action_text_rich_texts')
        rescue StandardError
          false
        end
      } do |user|
        user.biography&.body&.to_s
      end
      expose :biography_text, if: lambda { |user, _opts|
        user.respond_to?(:biography) && begin
          ActiveRecord::Base.connection.data_source_exists?('action_text_rich_texts')
        rescue StandardError
          false
        end
      } do |user|
        user.biography&.to_plain_text
      end
    end
  end
end
