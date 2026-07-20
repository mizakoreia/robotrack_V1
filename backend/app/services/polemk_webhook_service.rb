# frozen_string_literal: true

class PolemkWebhookService
  class << self
    def create_webhook(params)
      instance = PolemkInstance.first
      events = %w[SEND_MESSAGE MESSAGES_UPSERT MESSAGES_UPDATE CONNECTION_UPDATE LOGOUT_INSTANCE QRCODE_UPDATED]

      webhook_payload = {
        webhook: {
          enabled: true,
          url: params[:url],
          events: events,
          base64: true,
          byEvents: true
        }
      }

      EvolutionConnection.set_webhook(webhook_payload)

      events.each do |event|
        full_url = "#{params[:url]}/#{event.downcase.tr('_', '-')}"
        webhook = instance.polemk_webhooks.find_or_initialize_by(event: event)
        webhook.update(
          url: full_url,
          enabled: true,
          webhook_by_events: true,
          webhook_base_64: true,
          raw_response: webhook_payload
        )
      end

      result = Api::Entities::PolemkWebhook.represent(instance.polemk_webhooks).as_json

      format_response('Webhook configurado com sucesso', result)
    end

    def list(_params)
      response = EvolutionConnection.list_webhooks
      format_response('Webhooks listadas com sucesso', response)
    end

    def test_connection(url)
      uri = URI.parse(url)
      raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
        f.request :json
        f.adapter Faraday.default_adapter
      end

      path = uri.request_uri
      payload = { ping: 'ok', timestamp: Time.now.utc.iso8601 }
      resp = conn.post(path, payload, { 'Content-Type' => 'application/json' })

      {
        status: 'success',
        message: 'Webhook respondeu',
        data: { code: resp.status, body: resp.body }
      }
    rescue URI::InvalidURIError
      {
        status: 422,
        error: 'invalid_url',
        message: 'URL inválida'
      }
    rescue StandardError => e
      {
        status: 502,
        error: 'connection_error',
        message: e.message
      }
    end

    private

    def build_create_body(params)
      params.to_h.symbolize_keys.compact
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
