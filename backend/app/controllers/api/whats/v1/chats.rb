# frozen_string_literal: true

module Api
  module Whats
    module V1
      class Chats < Grape::API
        resource :check_number do
          desc 'Verificar numero do WhatsApp' do
            detail 'Consulta um ou mais números e informa se estão registrados no WhatsApp'
          end

          params do
            requires :numbers, type: Array, desc: 'Números de telefone a verificar'
          end

          post '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed
            PolemkChatService.check_number(params)
          end
        end
      end
    end
  end
end
