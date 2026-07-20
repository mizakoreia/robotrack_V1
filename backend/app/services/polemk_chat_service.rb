# frozen_string_literal: true

class PolemkChatService
  class << self
    def check_number(params)
      body = build_create_body(params)

      result = EvolutionConnection.check_number(body)
      response = result[:response]

      format_response('Numeros verificados com sucesso', response)
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
