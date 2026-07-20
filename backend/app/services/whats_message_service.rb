# frozen_string_literal: true

class WhatsMessageService
  class << self
    def send(params)
      # Garantir que envio seja feito em contexto de ClientApplication
      # Este serviço assume que autenticação já validou @current_client
      body = build_message_body(params)

      result = EvolutionConnection.send_message(body)

      ack = build_ack(result[:response])

      format_response('Mensagem enviada com sucesso', {
                        status: result[:status],
                        response: result[:response].merge({ ack: ack }.compact)
                      })
    end

    def instances(_params = {})
      response = EvolutionConnection.list_instances

      format_response('Instâncias listadas com sucesso', response)
    end

    def get_instance
      response = EvolutionConnection.get_instance

      format_response('Instância listada com sucesso', response)
    end

    private

    def build_message_body(params)
      {
        number: params[:number],
        text: params[:text],
        delay: params[:delay],
        presence: params[:presence],
        quoted: build_quoted(params[:quoted]),
        linkPreview: params[:link_preview],
        mentionsEveryOne: params[:mentions_every_one],
        mentioned: params[:mentions]
      }.compact
    end

    def build_quoted(quoted)
      return unless quoted.is_a?(Hash)

      {
        key: {
          remoteJid: quoted[:remote_jid],
          fromMe: quoted[:from_me],
          id: quoted[:id],
          participant: quoted[:participant]
        }.compact,
        message: {
          conversation: quoted[:conversation]
        }.compact
      }.compact
    end

    def format_response(message, response)
      {
        status: response[:status],
        message: message,
        data: response[:response]
      }
    end

    def build_ack(resp)
      return unless resp.is_a?(Hash)

      id = resp['id'] || resp.dig('key', 'id')
      status = resp['status'] || 'queued'
      { id: id, status: status }.compact
    end
  end
end
