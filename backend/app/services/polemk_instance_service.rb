# frozen_string_literal: true

class PolemkInstanceService
  class << self
    include ApiResponseHandler
    def create_instance(params)
      display_name = params[:display_name]

      instance_name = if params[:instance_name].present?
                        PolemkInstance.normalize_instance_name(params[:instance_name])
                      else
                        PolemkInstance.normalize_instance_name(display_name)
                      end

      def get_connection_status(params)
        instance = if params[:instance_id].present?
                     PolemkInstance.find_by(instance_id: params[:instance_id])
                   else
                     PolemkInstance.first
                   end

        return not_found_response('Instância') unless instance

        # Retorna status completo da conexão
        status_data = {
          instance_id: instance.instance_id,
          connection_status: instance.connection_status,
          connected: instance.connected?,
          waiting_qr: instance.waiting_qr?,
          qr_code_expired: instance.qr_code_expired?,
          qr_code_time_remaining: instance.qr_code_time_remaining,
          last_connection_at: instance.last_connection_at&.iso8601,
          last_logout_at: instance.last_logout_at&.iso8601,
          logout_reason: instance.logout_reason,
          last_qr_generated_at: instance.last_qr_generated_at&.iso8601
        }

        success_response(status_data, 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end

      def get_connection_status(params)
        instance = if params[:instance_id].present?
                     PolemkInstance.find_by(instance_id: params[:instance_id])
                   else
                     PolemkInstance.first
                   end

        return not_found_response('Instância') unless instance

        # Retorna status completo da conexão
        status_data = {
          instance_id: instance.instance_id,
          connection_status: instance.connection_status,
          connected: instance.connected?,
          waiting_qr: instance.waiting_qr?,
          qr_code_expired: instance.qr_code_expired?,
          qr_code_time_remaining: instance.qr_code_time_remaining,
          last_connection_at: instance.last_connection_at&.iso8601,
          last_logout_at: instance.last_logout_at&.iso8601,
          logout_reason: instance.logout_reason,
          last_qr_generated_at: instance.last_qr_generated_at&.iso8601
        }

        success_response(status_data, 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end

      # Cria o corpo da request com base nos parâmetros enviados + instanceName gerado
      body = build_create_body(params).merge(instanceName: instance_name)

      result = EvolutionConnection.create_instance(body)
      response = result[:response]

      instance = PolemkInstance.create!(
        display_name: display_name,
        instance_name: response.dig('instance', 'instanceName'),
        instance_id: response.dig('instance', 'instanceId'),
        integration: response.dig('instance', 'integration'),
        is_qrcode: params[:qrcode],
        api_key: response['hash'].is_a?(Hash) ? response['hash']['apikey'] : response['hash'],
        raw_response: response
      )
      result = Api::Entities::PolemkInstances.represent(instance).as_json

      format_response('Instância criada com sucesso', result)
    end

    def delete_instance(_params)
      response = EvolutionConnection.delete_instance
      format_response('Instância removida com sucesso', response[:response])
    end

    def logout_instance(_params)
      response = EvolutionConnection.logout_instance
      format_response('Instância desconectada com sucesso', response[:response])
    end

    def instance_connect_status(_params)
      response = EvolutionConnection.instance_connect_status
      format_response('Instância atual retornada com sucesso', response[:response])
    end

    def connect_instance(params)
      response = EvolutionConnection.connect_instance(params)
      format_response('Instância atual retornada com sucesso', response[:response])
    end

    def restart_instance(_params)
      response = EvolutionConnection.restart_instance
      format_response('Instância reiniciada com sucesso', response[:response])
    end

    def list(_params)
      response = EvolutionConnection.list_instances
      format_response('Instâncias listadas com sucesso', response[:response])
    end

    def get_instance(params)
      if params[:instance_id].present? && params[:instance_name].present?
        return validation_error_response('Parâmetros inválidos')
      end

      instance = if params[:instance_id].present?
                   PolemkInstance.find_by(instance_id: params[:instance_id]) || PolemkInstance.first
                 elsif params[:instance_name].present?
                   PolemkInstance.find_by(instance_name: params[:instance_name]) || PolemkInstance.first
                 else
                   PolemkInstance.first
                 end
      return not_found_response('Instância') unless instance

      success_response(Api::Entities::PolemkInstances.represent(instance).as_json, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def build_create_body(params)
      params.to_h.symbolize_keys.except(:display_name, :instance_name).compact
    end

    def format_response(message, response)
      {
        status: 'success',
        message: message,
        data: response
      }
    end
  end
end
