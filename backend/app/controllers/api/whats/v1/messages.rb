# frozen_string_literal: true

module Api
  module Whats
    module V1
      class Messages < Grape::API
        resource :send_message do
          desc 'Enviar mensagem' do
            detail 'Permite o envio de mensagens de texto para um número específico no WhatsApp. Suporta citação de mensagens, menções, delay e preview de links.'
          end

          params do
            requires :number, type: String, desc: 'Número do destinatário (ex: 5511999999999)'
            requires :text, type: String, desc: 'Conteúdo da mensagem'
            optional :delay, type: Integer, desc: 'Tempo em milissegundos para aguardar antes de enviar'
            optional :presence, type: String, desc: 'Status de presença: composing, available, etc.'
            optional :link_preview, type: Boolean, desc: 'Exibir preview de link, se houver'
            optional :quoted, type: Hash, desc: 'Mensagem a ser citada (estrutura depende da plataforma)'
            optional :mentions, type: Hash, desc: 'Hash com números mencionados na mensagem'
          end

          post '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed

            WhatsMessageService.send(params)
          end
        end
      end
    end
  end
end
