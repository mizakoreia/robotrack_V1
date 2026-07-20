# frozen_string_literal: true

class EvolutionConnection
  include HTTParty

  # Permite funcionar com variáveis do .env do backend
  # Prioriza WHATS_* e faz fallback para EVOLUTION_*
  BASE_URL = ENV['WHATS_SERVER_URL'] || ENV['EVOLUTION_BASE_URL']
  API_KEY  = ENV['WHATS_AUTHENTICATION_API_KEY'] || ENV['EVOLUTION_API_KEY']

  headers 'Content-Type' => 'application/json',
          'apikey' => API_KEY

  def self.instance
    @instance ||= PolemkInstance.first
  end

  def self.instance_id
    instance&.instance_id
  end

  def self.instance_name
    instance&.instance_name
  end

  def self.display_name
    instance&.display_name
  end

  def self.polemk_instance_id
    instance&.id
  end

  class ConnectionError < StandardError; end
  class TimeoutError < StandardError; end

  class InvalidResponseError < StandardError
    attr_reader :status, :error, :details

    def initialize(response)
      @status  = response['status'] || 'error'
      @error   = response['error'] || 'Unknown Error'
      @details = response['response'] || response

      super("API Error: #{@error} - #{@details}")
    end

    def as_json(*)
      {
        status: status,
        error: error,
        details: details
      }
    end
  end

  def self.request(method, endpoint, body: nil)
    ensure_config!
    url = "#{BASE_URL}#{endpoint}"
    options = body ? { body: JSON.generate(body) } : {}

    response = public_send(method, url, options)
    parsed = response.parsed_response

    raise InvalidResponseError, parsed unless response.success?

    { status: 'success', response: parsed }
  rescue InvalidResponseError => e
    raise e
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    raise TimeoutError, "Timeout ao se conectar com o Evolution API: #{e.message}"
  rescue SocketError => e
    raise ConnectionError, "Erro de conexão com o Evolution API: #{e.message}"
  rescue StandardError => e
    raise ConnectionError, "Erro desconhecido ao se conectar com Evolution: #{e.message}"
  end

  # Garante que as variáveis de ambiente necessárias estão presentes
  def self.ensure_config!
    missing = []
    missing << 'WHATS_SERVER_URL/EVOLUTION_BASE_URL' if BASE_URL.nil? || BASE_URL.empty?
    missing << 'WHATS_AUTHENTICATION_API_KEY/EVOLUTION_API_KEY' if API_KEY.nil? || API_KEY.empty?

    return if missing.empty?

    raise ConnectionError, "Configuração ausente: #{missing.join(', ')}. Verifique o arquivo .env do backend."
  end

  def self.create_instance(params)
    request(:post, '/instance/create', body: params)
  end

  def self.delete_instance
    request(:delete, "/instance/delete/#{instance_name}")
  end

  def self.logout_instance
    request(:delete, "/instance/logout/#{instance_name}")
  end

  def self.restart_instance
    request(:post, "/instance/restart/#{instance_name}")
  end

  def self.list_instances(params)
    search_param = params[:instance_name].present? ? "?instanceName=#{params[:instance_name]}" : ''
    request(:get, "/instance/fetchInstances#{search_param}")
  end

  def self.connect_instance(params)
    number_param = params[:number].present? ? "?number=#{params[:number]}" : ''
    endpoint = "/instance/connect/#{instance_name}#{number_param}"

    request(:get, endpoint)
  end

  def self.instance_connect_status
    request(:get, "/instance/connectionState/#{instance_name}")
  end

  def self.set_webhook(body)
    request(:post, "/webhook/set/#{instance_name}", body: body)
  end

  def self.send_message(body)
    request(:post, "/message/sendText/#{instance_name}", body: body)
  end

  def self.send_media(body)
    request(:post, "/message/sendMedia/#{instance_name}", body: body)
  end

  def self.create_webhook(body)
    request(:post, "/webhook/set/#{instance_name}", body: body)
  end

  def self.list_webhooks
    request(:get, "/webhook/find/#{instance_name}")
  end

  def self.check_number(body)
    request(:post, "/chat/whatsappNumbers/#{instance_name}", body: body)
  end

  def self.create_group(body)
    enriched_body = body.merge(subject: display_name) if display_name.present?
    result = request(:post, "/group/create/#{instance_name}", body: enriched_body)
    PolemkInstanceGroup.create!(
      group_id: result[:response]['id'],
      group_name: result[:response]['subject'],
      polemk_instance_id: polemk_instance_id,
      raw_response: result[:response]
    )

    image_path = Rails.root.join('app', 'assets', 'brand', 'images', 'app_symbol.png')
    base64_image = Base64.strict_encode64(File.read(image_path))
    body_image = {
      image: base64_image
    }

    request(:post, "/group/updateGroupPicture/#{instance_name}?groupJid=#{result[:response]['id']}", body: body_image)

    params_remove_participant = {
      action: 'remove',
      participants: [
        '5548984567304'
      ]
    }
    request(:post, "/group/updateParticipant/#{instance_name}?groupJid=#{result[:response]['id']}",
            body: params_remove_participant)

    result
  end
end
