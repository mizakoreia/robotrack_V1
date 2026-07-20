# frozen_string_literal: true

module ApiResponseHandler
  def success_response(data = {}, status = 200)
    {
      success: true,
      data: data,
      status: status
    }
  end

  def error_response(message, status = 422, details: nil)
    payload = {
      success: false,
      error: message,
      status: status
    }
    payload[:details] = details if details
    payload
  end

  def not_found_response(resource = 'Registro')
    error_response("#{resource} não encontrado", 404)
  end

  def validation_error_response(message, details: nil)
    error_response(message, 422, details: details)
  end

  def internal_error_response(message = 'Erro interno no servidor')
    error_response(message, 500)
  end

  def unauthorized_response(message = 'Não autorizado')
    error_response(message, 401)
  end

  def forbidden_response(message = 'Acesso negado')
    error_response(message, 403)
  end

  def conflict_response(message = 'Conflito')
    error_response(message, 409)
  end

  def rate_limit_response(message = 'Muitas tentativas. Tente novamente mais tarde')
    error_response(message, 429)
  end

  def process_service_response(result)
    status = result[:status] || 200

    if result[:success]
      present result[:data], with: Entities::Success # se usar Entities opcionalmente
      status status
    else
      error!(result, status)
    end
  end
end
