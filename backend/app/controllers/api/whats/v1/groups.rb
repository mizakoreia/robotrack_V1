# frozen_string_literal: true

module Api
  module Whats
    module V1
      class Groups < Grape::API
        before do
          allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
          error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed
        end
        resource :create do
          desc 'Criar um grupo' do
            detail 'Cria um novo grupo com a descrição informada e adiciona os participantes, se fornecidos. Ideal para segmentar o recebimento de mensagens dentro da plataforma.'
          end

          params do
            requires :description, type: String, desc: 'Descrição do grupo'
            requires :participants, type: Array[String], desc: 'Números que irão participar do grupo'
          end

          post '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkGroupService.create_group(params)
          end
        end
      end
    end
  end
end
