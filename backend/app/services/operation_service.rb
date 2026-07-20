# frozen_string_literal: true

# Service responsável por gerenciar operações de negócio (Business Operations)
# Implementa os métodos CRUD e busca de operações através da API
class OperationService
  class << self
    include ApiResponseHandler

    # Lista todas as operações com suporte a paginação e busca
    def list(params)
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || params[:l] || 20).to_i
      page = 1 if page <= 0
      per_page = 20 if per_page <= 0

      scope = Operation.all

      if params[:q].present?
        q = params[:q]
        scope = scope.where('key ILIKE ? OR title ILIKE ? OR description ILIKE ?',
                            "%#{q}%", "%#{q}%", "%#{q}%")
      end

      if params[:active].present?
        is_active = params[:active].to_s.downcase == 'true'
        scope = scope.where(active: is_active)
      end

      # Ordenação customizada
      if params[:ordering_keys].present?
        ordering_keys = Array(params[:ordering_keys])
        ordering_style = Array(params[:ordering_style] || [])
        operations_order = Operation.prepare_ordering(ordering_keys, ordering_style)
        scope = scope.order(operations_order)
      else
        scope = scope.order(created_at: :desc)
      end

      total = scope.count

      # Offset direto (compatível com console), senão paginação padrão
      if params[:o].present?
        offset = params[:o].to_i
        operations = scope.limit(per_page).offset(offset)
      else
        operations = scope.offset((page - 1) * per_page).limit(per_page)
      end

      success_response({
                         operations: Api::Entities::Operation.represent(operations).as_json,
                         total: total
                       }, 200)
    end

    # Recupera uma operação específica por ID
    def get(id)
      operation = Operation.by_any_id(id)
      return not_found_response('Operation') unless operation

      success_response(Api::Entities::Operation.represent(operation).as_json, 200)
    end

    # Método para obter estatísticas do dashboard
    def dashboard_stats
      total_operations = Operation.count
      active_operations = Operation.where(active: true).count
      total_leads = Lead.count

      # Distribuição de leads por operação (usando campo leads_count)
      operations_with_leads = Operation.where(active: true)
                                       .where('leads_count > 0')
                                       .select(:id, :key, :title, :leads_count)
                                       .map do |operation|
        {
          id: operation.id,
          key: operation.key,
          title: operation.title,
          leads_count: operation.leads_count
        }
      end

      success_response({
                         total_operations: total_operations,
                         active_operations: active_operations,
                         total_leads: total_leads,
                         operations_distribution: operations_with_leads
                       }, 200)
    end

    # Cria uma nova operação
    def create(params)
      process_keywords_param(params)
      operation = Operation.create!(params)
      success_response(Api::Entities::Operation.represent(operation).as_json, 201)
    rescue ActiveRecord::RecordInvalid => e
      validation_error_response(e.message)
    end

    # Atualiza uma operação existente
    def update(params)
      id = params.delete(:id)
      operation = Operation.by_any_id(id)
      return not_found_response('Operation') unless operation

      begin
        process_keywords_param(params)
        operation.update!(params)
        success_response(Api::Entities::Operation.represent(operation).as_json, 200)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      end
    end

    # Remove uma operação
    def destroy(id)
      operation = Operation.by_any_id(id)
      return not_found_response('Operation') unless operation

      begin
        operation.destroy!
        no_content_response
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    # Valida um texto contra as operações ativas e retorna a operação correspondente
    def validate(text)
      return validation_error_response('Text parameter is required') if text.blank?

      operation = Operation.find_by_text(text)

      if operation
        success_response(
          {
            matched: true,
            operation: Api::Entities::Operation.represent(operation).as_json
          },
          200
        )
      else
        success_response({ matched: false }, 200)
      end
    end

    private

    # Processa parâmetros de keywords tanto quando vêm como string (keywords ou keywords_string)
    def process_keywords_param(params)
      if params[:keywords_string].present? && params[:keywords_string].is_a?(String)
        params[:keywords] = params[:keywords_string].split(',').map(&:strip).reject(&:blank?)
        params.delete(:keywords_string)
      elsif params[:keywords].present? && params[:keywords].is_a?(String)
        params[:keywords] = params[:keywords].split(',').map(&:strip).reject(&:blank?)
      end
    end
  end
end
