# frozen_string_literal: true

class UsersService
  class << self
    include ApiResponseHandler

    # Busca usuário por WhatsApp e retorna entity ou URL de login
    def find_by_whatsapp(params)
      whatsapp = params[:whatsapp]&.gsub(/\D/, '')
      return validation_error_response('WhatsApp inválido') if whatsapp.blank?

      begin
        user = User.find_by(phone: whatsapp)
        if user
          success_response(Api::Entities::User.represent(user), 200)
        else
          error_response({ login_url: '/login' }, 404)
        end
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    # Atualização padrão por ID (sem integração com WhatsApp)
    def update(params)
      id = params.delete(:id)
      user = User.find_by(id: id)
      return not_found_response('Usuário') unless user

      begin
        update_params = params.slice(:email, :phone, :name, :avatar_url, :user_type_id,
                                     :cpf_cnpj, :cep, :street, :number, :complement, :district, :city, :state).compact
        if update_params[:user_type_id].blank? && params[:user_type].present?
          type = UserType.where('LOWER(name) = ?', params[:user_type].to_s.downcase).first
          update_params[:user_type_id] = type&.id
        end
        user.assign_attributes(update_params)
        user.biography = params[:biography] if params[:biography].present?
        user.save!
        success_response(Api::Entities::User.represent(user), 200)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def index(params)
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      q = params[:q].to_s.strip
      type = params[:type].to_s.strip.downcase

      begin
        scope = User.all
        if q.present?
          like = "%#{q.downcase}%"
          digits = q.gsub(/\D/, '')
          scope = if digits.present?
                    scope.where(
                      'LOWER(name) LIKE ? OR LOWER(email) LIKE ? OR phone LIKE ?',
                      like, like, "%#{digits}%"
                    )
                  else
                    scope.where(
                      'LOWER(name) LIKE ? OR LOWER(email) LIKE ?',
                      like, like
                    )
                  end
        end
        if type.present? && %w[og client].include?(type)
          ids = UserType.where('LOWER(name) = ?', type).pluck(:id)
          scope = scope.where(user_type_id: ids)
        end

        total = scope.except(:limit, :offset, :order).count
        users = scope.order(created_at: :desc).limit(per_page).offset((page - 1) * per_page)
        data = { users: Api::Entities::User.represent(users), total: total }
        success_response(data, 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def create(params)
      attrs = params.slice(:email, :phone, :name, :avatar_url, :user_type_id,
                           :cpf_cnpj, :cep, :street, :number, :complement, :district, :city, :state).compact
      return validation_error_response('Informe email ou telefone') if attrs[:email].blank? && attrs[:phone].blank?

      if attrs[:user_type_id].blank?
        type = UserType.where('LOWER(name) = ?',
                              (params[:user_type] || 'client').to_s.downcase).first || UserType.client
        attrs[:user_type_id] = type&.id
      end
      user = User.create!(attrs)
      success_response(Api::Entities::User.represent(user), 201)
    rescue ActiveRecord::RecordInvalid => e
      validation_error_response(e.message)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def show(params)
      user = User.find_by(id: params[:id])
      return not_found_response('Usuário') unless user

      success_response(Api::Entities::User.represent(user), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def destroy(params)
      user = User.find_by(id: params[:id])
      return not_found_response('Usuário') unless user

      user.destroy!
      success_response({}, 204)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def stats(_params)
      total = User.count
      active = User.active.count
      recent = User.where('created_at >= ?', 7.days.ago).count
      og_id = UserType.where('LOWER(name) = ?', 'og').pluck(:id)
      client_id = UserType.where('LOWER(name) = ?', 'client').pluck(:id)
      og_count = User.where(user_type_id: og_id).count
      client_count = User.where(user_type_id: client_id).count
      data = {
        total: total,
        active: active,
        recent: recent,
        og_count: og_count,
        client_count: client_count
      }
      success_response(data, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end
  end
end
