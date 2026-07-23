# frozen_string_literal: true

module Api
  module V1
    # Sonda de saúde (offline-pwa 4.3 / D7-4). A fila offline usa `HEAD
    # /api/v1/health` como PORTEIRO da drenagem: um único toque barato antes de
    # disparar os envios, para que um Wi-Fi de galpão sem rota de saída produza
    # UMA sonda e não 40 requisições. Sem tenant e sem auth — é só "o servidor
    # responde?". Grape atende HEAD por meio do handler de GET (corpo descartado).
    class Health < Grape::API
      format :json

      resource :health do
        desc 'Sonda de saúde — 200 quando o servidor está de pé'
        get do
          status 200
          { status: 'ok' }
        end
      end
    end
  end
end
