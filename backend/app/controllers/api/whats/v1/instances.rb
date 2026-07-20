# frozen_string_literal: true

module Api
  module Whats
    module V1
      class Instances < Grape::API
        helpers do
          def process_service_response(response)
            status response[:status]

            if (200..299).include?(response[:status])
              response[:data]
            else
              error_payload = { error: response[:error] || response[:message] }
              error_payload[:details] = response[:details] if response[:details]
              error!(error_payload, response[:status])
            end
          end
        end

        before do
          allowed = (defined?(@current_client) && @current_client.present?) || (defined?(@current_user) && @current_user&.og?)
          error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed
        end
        resource :instance do
          desc 'Obter instância atual' do
            detail "Retorna os dados da instância registrada no banco de dados. Permite buscar por 'instance_id' ou 'instance_name'."
          end

          desc 'Obter status de conexão da instância' do
            detail 'Retorna o status atual da conexão WhatsApp, incluindo estado, QR Code e informações de conexão'
          end

          params do
            optional :instance_id, type: String, desc: 'ID da instância'
          end

          get 'connection-status', http_codes: [
            [200, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            process_service_response(PolemkInstanceService.get_connection_status(params))
          end

          params do
            optional :instance_id, type: String, desc: 'ID da instância'
            optional :instance_name, type: String, desc: 'Nome da instância'
          end

          get '', http_codes: [
            [200, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            process_service_response(PolemkInstanceService.get_instance(params))
          end
        end

        resource :create_instance do
          desc 'Criar instância' do
            detail 'Cria uma nova instância de conexão com o WhatsApp, podendo configurar integração, proxy, webhook, filas e integração com Chatwoot.'
          end

          params do
            requires :display_name, type: String, desc: 'Nome da instância exibido na interface'
            optional :instance_name, type: String, desc: 'Identificador único da instância (opcional)'
            requires :integration, type: String, values: %w[WHATSAPP-BAILEYS WHATSAPP-BUSINESS],
                                   desc: 'Tipo de integração com o WhatsApp'

            optional :qrcode, type: Boolean, default: true, desc: 'Indica se o QR Code deve ser retornado'
            optional :number, type: String, desc: 'Número de telefone associado à instância'

            optional :rejectCall, type: Boolean, desc: 'Recusar chamadas recebidas automaticamente'
            optional :msgCall, type: String, desc: 'Mensagem enviada ao recusar chamadas'
            optional :groupsIgnore, type: Boolean, desc: 'Ignorar mensagens de grupos'
            optional :alwaysOnline, type: Boolean, desc: 'Manter instância online continuamente'
            optional :readMessages, type: Boolean, desc: 'Marcar mensagens como lidas automaticamente'
            optional :readStatus, type: Boolean, desc: 'Marcar status como visualizados automaticamente'
            optional :syncFullHistory, type: Boolean, desc: 'Sincronizar histórico completo ao conectar'

            optional :proxyHost, type: String, desc: 'Endereço do servidor proxy'
            optional :proxyPort, type: String, desc: 'Porta do proxy'
            optional :proxyProtocol, type: String, desc: 'Protocolo utilizado pelo proxy (ex: http, socks5)'
            optional :proxyUsername, type: String, desc: 'Usuário de autenticação do proxy'
            optional :proxyPassword, type: String, desc: 'Senha de autenticação do proxy'

            optional :webhook, type: Hash do
              requires :url, type: String, desc: 'URL para onde os webhooks serão enviados'
              optional :byEvents, type: Boolean, desc: 'Indica se os eventos serão enviados separadamente'
              optional :base64, type: Boolean, desc: 'Enviar conteúdo dos arquivos em base64'
              optional :headers, type: Hash do
                optional :authorization, type: String, desc: 'Header de autorização para chamadas ao webhook'
                optional :content_type, type: String, desc: 'Content-Type a ser enviado nas chamadas do webhook'
              end
              optional :events, type: Array[String], desc: 'Lista de eventos que devem acionar o webhook'
            end

            optional :rabbitmq, type: Hash do
              requires :enabled, type: Boolean, desc: 'Habilita o envio de mensagens via RabbitMQ'
              optional :events, type: Array[String], desc: 'Eventos específicos que serão enviados para a fila'
            end

            optional :sqs, type: Hash do
              requires :enabled, type: Boolean, desc: 'Habilita o envio de mensagens via AWS SQS'
              optional :events, type: Array[String], desc: 'Eventos específicos que serão enviados para a fila'
            end

            optional :chatwootAccountId, type: Integer, desc: 'ID da conta Chatwoot'
            optional :chatwootToken, type: String, desc: 'Token da conta Chatwoot'
            optional :chatwootUrl, type: String, desc: 'URL base da instância Chatwoot'
            optional :chatwootSignMsg, type: Boolean, desc: 'Assinar mensagens enviadas com nome do atendente'
            optional :chatwootReopenConversation, type: Boolean,
                                                  desc: 'Reabrir conversa automaticamente ao receber mensagem'
            optional :chatwootConversationPending, type: Boolean, desc: 'Definir nova conversa como pendente'
            optional :chatwootImportContacts, type: Boolean, desc: 'Importar contatos automaticamente do WhatsApp'
            optional :chatwootNameInbox, type: String, desc: 'Nome da inbox criada no Chatwoot'
            optional :chatwootMergeBrazilContacts, type: Boolean, desc: 'Unificar contatos com DDD +55 no Chatwoot'
            optional :chatwootImportMessages, type: Boolean, desc: 'Importar histórico de mensagens anteriores'
            optional :chatwootDaysLimitImportMessages, type: Integer,
                                                       desc: 'Quantidade de dias retroativos ao importar mensagens'
            optional :chatwootOrganization, type: String, desc: 'Organização do Chatwoot'
            optional :chatwootLogo, type: String, desc: 'Logo da inbox a ser exibida no Chatwoot'
          end

          post '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.create_instance(params)
          end
        end

        resource :delete_instance do
          desc 'Remover instância' do
            detail 'Remove a instância conectada atualmente ao serviço do WhatsApp.'
          end

          params {}

          delete '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.delete_instance(params)
          end
        end

        resource :logout_instance do
          desc 'Desconectar instância' do
            detail 'Desconecta a instância ativa, encerrando a sessão no WhatsApp.'
          end

          params {}

          get '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.logout_instance(params)
          end
        end

        resource :list_instances do
          desc 'Listar instâncias' do
            detail 'Retorna a lista de instâncias disponíveis com seus respectivos estados.'
          end

          params {}

          get '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.list(params)
          end
        end

        resource :connect_instance do
          desc 'Obter QR Code' do
            detail 'Retorna o QR Code e o código da instância, para que o usuário possa parear com o WhatsApp.'
          end

          params do
            optional :number, type: String, desc: "Número de telefone sem o símbolo '+'"
          end

          get '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.connect_instance(params)
          rescue EvolutionConnection::TimeoutError
            error!({ error: 'timeout', message: 'Evolution sem resposta. Tente novamente.' }, 504)
          rescue EvolutionConnection::ConnectionError => e
            error!({ error: 'connection_error', message: e.message }, 502)
          end
        end

        resource :instance_connect_status do
          desc 'Status da conexão' do
            detail 'Verifica o status atual da instância: conectado, desconectado, aguardando conexão, etc.'
          end

          params {}

          get '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.instance_connect_status(params)
          rescue EvolutionConnection::TimeoutError
            error!({ error: 'timeout', message: 'Evolution sem resposta. Tente novamente.' }, 504)
          rescue EvolutionConnection::ConnectionError => e
            error!({ error: 'connection_error', message: e.message }, 502)
          end
        end

        resource :restart_instance do
          desc 'Reiniciar instância' do
            detail 'Solicita reinício da instância ativa no Evolution API.'
          end

          params {}

          post '', http_codes: [
            [201, 'Ok'],
            [401, 'Unauthorized'],
            [404, 'Not Found'],
            [500, 'Internal Server Error']
          ] do
            PolemkInstanceService.restart_instance(params)
          rescue EvolutionConnection::TimeoutError
            error!({ error: 'timeout', message: 'Evolution sem resposta. Tente novamente.' }, 504)
          rescue EvolutionConnection::ConnectionError => e
            error!({ error: 'connection_error', message: e.message }, 502)
          end
        end
      end
    end
  end
end
