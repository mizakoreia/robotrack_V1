# frozen_string_literal: true

class PolemkGroupService
  class << self
    def create_group(params)
      body = build_create_body(params)

      result = EvolutionConnection.create_group(body)
      response = result[:response]

      format_response('Grupo criado com sucesso', response)
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
