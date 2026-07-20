# frozen_string_literal: true

module Api
  module V1
    class Leads < Grape::API
      helpers Api::V1::ControllerHelpers

      # ===============================================
      # LEADS - CRUD RESTFUL COMPLETO
      # ===============================================

      # GET /api/v1/leads - Listar leads
      resource '' do
        desc 'Listar leads' do
          summary 'Listar leads'
          detail 'Retorna uma lista de leads filtrados por parâmetros.'
          success [code: 200, message: 'Ok', model: Api::Entities::Lead]
          is_array true
        end

        params do
          optional :o, type: Integer, desc: 'Offset'
          optional :l, type: Integer, desc: 'Limit'
          optional :q, type: String, desc: 'Query de busca'
        end

        get '', http_codes: [
          [401, 'Unauthorized'],
          [500, 'Internal Server Error']
        ] do
          response = LeadService.list(params)
          process_service_response(response)
        end
      end

      # POST /api/v1/leads - Criar lead
      resource '' do
        desc 'Criar lead' do
          summary 'Criar lead'
          detail 'Cria um novo lead.'
          success [code: 201, message: 'Created', model: Api::Entities::Lead]
        end

        params do
          requires :source_type, type: String, desc: 'Tipo de origem'
          requires :source_id, type: String, desc: 'ID da origem'
          optional :current_stage, type: String, desc: 'Estágio atual'
          optional :name, type: String, desc: 'Nome do lead'
          optional :phone, type: String, desc: 'Telefone'
          optional :ig_username, type: String, desc: 'Username Instagram'
          optional :company_name, type: String, desc: 'Nome da empresa'
          optional :has_site, type: Boolean, desc: 'Possui site'
          optional :site_url, type: String, desc: 'URL do site'
          optional :site_scrapped_text, type: String, desc: 'Texto do site'
          optional :intention, type: String, desc: 'Intenção'
          optional :instruction, type: String, desc: 'Instrução'
          optional :discovery_level, type: Integer, desc: 'Nível discovery'
          optional :enchantment_level, type: Integer, desc: 'Nível enchantment'
          optional :closing_level, type: Integer, desc: 'Nível closing'

          optional :igs_id, type: String, desc: 'ID numérico do Instagram'
          optional :fb_id, type: String, desc: 'ID numérico do Facebook'
          optional :fb_username, type: String, desc: 'Username do Facebook'
          optional :target_id, type: String, desc: 'Identificador da aplicação na fonte de origem'
          optional :execution_id, type: String, desc: 'ID da execução/campanha associada'

          optional :is_categorized, type: Boolean, desc: 'Se o lead já foi categorizado explicitamente'
          optional :content, type: String, desc: 'Conteúdo da última mensagem'
          optional :content_type, type: String,
                                  desc: 'Tipo da última mensagem (text, image, audio, video, file, ephemeral)'
          optional :content_id, type: String, desc: 'ID da mensagem/mídia na fonte original'
          optional :source_endpoint, type: String, desc: 'Tipo de interação inicial (message, comment, reaction, call)'

          # ===============================================
          # CRITÉRIOS DE ENCANTAMENTO - ALGORITMO DE VENDAS
          # ===============================================
          optional :understands_goals, type: String,
                                       desc: 'Critério de encantamento: Cliente entendeu que o objetivo é criar sites únicos e memoráveis no nicho'
          optional :understands_smart_navigation, type: String,
                                                  desc: 'Critério de encantamento: Cliente compreendeu navegação inteligente e estrutura diferenciada'
          optional :understands_complexity, type: String,
                                            desc: 'Critério de encantamento: Cliente entendeu diferença entre soluções personalizadas vs genéricas (WordPress)'
          optional :understands_thats_exclusive, type: String,
                                                 desc: 'Critério de encantamento: Cliente compreendeu que terá site exclusivo, não adaptado de template'
          optional :understands_thats_memorable, type: String,
                                                 desc: 'Critério de encantamento: Cliente concordou que sites personalizados são mais memoráveis'
          optional :likes_some_site, type: String,
                                     desc: 'Critério de encantamento: Cliente demonstrou gostar de algum site do portfólio'
          optional :likes_some_app, type: String,
                                    desc: 'Critério de encantamento: Cliente demonstrou interesse em app/funcionalidade apresentada'
          optional :knows_app1_site, type: String,
                                     desc: 'Critério de encantamento: Cliente viu exemplo de site/app 1'
          optional :knows_app2_site, type: String,
                                     desc: 'Critério de encantamento: Cliente viu exemplo de site/app 2'
          optional :knows_app3_site, type: String,
                                     desc: 'Critério de encantamento: Cliente viu exemplo de site/app 3'
          optional :knows_console_mod, type: String,
                                       desc: 'Critério de encantamento: Cliente entendeu que terá painel administrativo para gerenciar conteúdo'
          optional :knows_whats_mod, type: String,
                                     desc: 'Critério de encantamento: Cliente foi apresentado à integração WhatsApp e possibilidades futuras'
          optional :knows_own_demand, type: String,
                                      desc: 'Critério de encantamento: Demanda específica identificada e registrada pelo agente'

          # ===============================================
          # CRITÉRIOS DE FECHAMENTO - ALGORITMO DE VENDAS
          # ===============================================
          optional :validated_interest, type: String,
                                        desc: 'Critério de fechamento: Cliente demonstrou interesse claro no projeto antes da reunião'
          optional :understands_value, type: String,
                                       desc: 'Critério de fechamento: Cliente compreendeu o valor da proposta e o que está incluído nos serviços'
          optional :received_proposal, type: String,
                                       desc: 'Critério de fechamento: Cliente recebeu e acessou o link do orçamento/proposta comercial'
          optional :gave_feedback, type: String,
                                   desc: 'Critério de fechamento: Cliente forneceu feedback sobre a proposta apresentada'
          optional :ready_to_schedule, type: String,
                                       desc: 'Critério de fechamento: Cliente demonstrou intenção de avançar e agendar próximos passos'
        end

        post '', http_codes: [
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [500, 'Internal Server Error']
        ] do
          response = LeadService.create(params)
          process_service_response(response)
        end
      end

      # GET /api/v1/leads/:id - Buscar lead específico
      resource '' do
        desc 'Buscar lead específico' do
          summary 'Buscar lead específico'
          detail 'Retorna os detalhes de um lead usando by_any_id (ID, smart_id, session_uuid, telefone).'
          success [code: 200, message: 'Ok', model: Api::Entities::Lead]
        end

        params do
          requires :id, type: String, desc: 'ID do lead (aceita ID numérico, smart_id, session_uuid ou telefone)'
        end

        get ':id', http_codes: [
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          response = LeadService.get_lead(params[:id])
          process_service_response(response)
        end
      end

      # PUT /api/v1/leads/:id - Atualizar lead
      resource '' do
        desc 'Atualizar lead' do
          summary 'Atualizar lead'
          detail 'Atualiza um lead existente usando by_any_id.'
          success [code: 200, message: 'Updated', model: Api::Entities::Lead]
        end

        params do
          requires :id, type: String, desc: 'ID do lead (aceita ID numérico, smart_id, session_uuid ou telefone)'
          optional :current_stage, type: String, desc: 'Estágio atual'
          optional :name, type: String, desc: 'Nome do lead'
          optional :phone, type: String, desc: 'Telefone'
          optional :ig_username, type: String, desc: 'Username Instagram'
          optional :company_name, type: String, desc: 'Nome da empresa'
          optional :has_site, type: Boolean, desc: 'Possui site'
          optional :site_url, type: String, desc: 'URL do site'
          optional :site_scrapped_text, type: String, desc: 'Texto do site'
          optional :intention, type: String, desc: 'Intenção'
          optional :instruction, type: String, desc: 'Instrução'
          optional :discovery_level, type: Integer, desc: 'Nível discovery'
          optional :enchantment_level, type: Integer, desc: 'Nível enchantment'
          optional :closing_level, type: Integer, desc: 'Nível closing'

          optional :igs_id, type: String, desc: 'ID numérico do Instagram'
          optional :fb_id, type: String, desc: 'ID numérico do Facebook'
          optional :fb_username, type: String, desc: 'Username do Facebook'
          optional :target_id, type: String, desc: 'Identificador da aplicação na fonte de origem'
          optional :execution_id, type: String, desc: 'ID da execução/campanha associada'

          optional :is_categorized, type: Boolean, desc: 'Se o lead já foi categorizado explicitamente'
          optional :content, type: String, desc: 'Conteúdo da última mensagem'
          optional :content_type, type: String,
                                  desc: 'Tipo da última mensagem (text, image, audio, video, file, ephemeral)'
          optional :content_id, type: String, desc: 'ID da mensagem/mídia na fonte original'
          optional :source_endpoint, type: String, desc: 'Tipo de interação inicial (message, comment, reaction, call)'

          # ===============================================
          # CRITÉRIOS DE ENCANTAMENTO - ALGORITMO DE VENDAS
          # ===============================================
          optional :understands_goals, type: String,
                                       desc: 'Critério de encantamento: Cliente entendeu que o objetivo é criar sites únicos e memoráveis no nicho'
          optional :understands_smart_navigation, type: String,
                                                  desc: 'Critério de encantamento: Cliente compreendeu navegação inteligente e estrutura diferenciada'
          optional :understands_complexity, type: String,
                                            desc: 'Critério de encantamento: Cliente entendeu diferença entre soluções personalizadas vs genéricas (WordPress)'
          optional :understands_thats_exclusive, type: String,
                                                 desc: 'Critério de encantamento: Cliente compreendeu que terá site exclusivo, não adaptado de template'
          optional :understands_thats_memorable, type: String,
                                                 desc: 'Critério de encantamento: Cliente concordou que sites personalizados são mais memoráveis'
          optional :likes_some_site, type: String,
                                     desc: 'Critério de encantamento: Cliente demonstrou gostar de algum site do portfólio'
          optional :likes_some_app, type: String,
                                    desc: 'Critério de encantamento: Cliente demonstrou interesse em app/funcionalidade apresentada'
          optional :knows_app1_site, type: String,
                                     desc: 'Critério de encantamento: Cliente viu exemplo de site/app 1'
          optional :knows_app2_site, type: String,
                                     desc: 'Critério de encantamento: Cliente viu exemplo de site/app 2'
          optional :knows_app3_site, type: String,
                                     desc: 'Critério de encantamento: Cliente viu exemplo de site/app 3'
          optional :knows_console_mod, type: String,
                                       desc: 'Critério de encantamento: Cliente entendeu que terá painel administrativo para gerenciar conteúdo'
          optional :knows_whats_mod, type: String,
                                     desc: 'Critério de encantamento: Cliente foi apresentado à integração WhatsApp e possibilidades futuras'
          optional :knows_own_demand, type: String,
                                      desc: 'Critério de encantamento: Demanda específica identificada e registrada pelo agente'

          # ===============================================
          # CRITÉRIOS DE FECHAMENTO - ALGORITMO DE VENDAS
          # ===============================================
          optional :validated_interest, type: String,
                                        desc: 'Critério de fechamento: Cliente demonstrou interesse claro no projeto antes da reunião'
          optional :understands_value, type: String,
                                       desc: 'Critério de fechamento: Cliente compreendeu o valor da proposta e o que está incluído nos serviços'
          optional :received_proposal, type: String,
                                       desc: 'Critério de fechamento: Cliente recebeu e acessou o link do orçamento/proposta comercial'
          optional :gave_feedback, type: String,
                                   desc: 'Critério de fechamento: Cliente forneceu feedback sobre a proposta apresentada'
          optional :ready_to_schedule, type: String,
                                       desc: 'Critério de fechamento: Cliente demonstrou intenção de avançar e agendar próximos passos'
        end

        put ':id', http_codes: [
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          # Passa o id nos params para o service
          update_params = params.dup
          response = LeadService.update(update_params)
          process_service_response(response)
        end
      end

      resource '' do
        desc 'Adicionar desire ao lead' do
          summary 'Adicionar desire ao lead'
          detail 'Adiciona um novo desire ao array de desires do lead.'
          success [code: 200, message: 'Ok', model: Api::Entities::Lead]
        end

        params do
          requires :id, type: String, desc: 'ID do lead (aceita ID numérico, smart_id, session_uuid ou telefone)'
          requires :desire, type: String, desc: 'Texto do desire a ser adicionado'
        end

        post ':id/desires', http_codes: [
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          response = LeadService.add_desire(params)
          process_service_response(response)
        end
      end

      resource '' do
        desc 'Remover desire do lead' do
          summary 'Remover desire do lead'
          detail 'Remove um desire do array de desires do lead pelo índice.'
          success [code: 200, message: 'Ok', model: Api::Entities::Lead]
        end

        params do
          requires :id, type: String, desc: 'ID do lead (aceita ID numérico, smart_id, session_uuid ou telefone)'
          requires :index, type: Integer, desc: 'Índice do desire a ser removido (base 0)'
        end

        delete ':id/desires/:index', http_codes: [
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          response = LeadService.remove_desire(params)
          process_service_response(response)
        end
      end

      # DELETE /api/v1/leads/:id - Deletar lead
      resource '' do
        desc 'Deletar lead' do
          summary 'Deletar lead'
          detail 'Remove um lead usando by_any_id.'
          success [code: 204, message: 'No Content']
        end

        params do
          requires :id, type: String, desc: 'ID do lead (aceita ID numérico, smart_id, session_uuid ou telefone)'
        end

        delete ':id', http_codes: [
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          response = LeadService.destroy(params[:id])
          process_service_response(response)
        end
      end

      # ===============================================
      # MENSAGENS - CRUD RESTFUL (SEM UPDATE)
      # ===============================================

      # GET /api/v1/leads/:lead_id/messages - Listar mensagens do lead
      resource '' do
        desc 'Listar mensagens do lead' do
          summary 'Listar mensagens do lead'
          detail 'Retorna uma lista de mensagens do lead filtradas por parâmetros.'
          success [code: 200, message: 'Ok', model: Api::Entities::LeadMessage]
          is_array true
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead (aceita qualquer formato via by_any_id)'
          optional :o, type: Integer, desc: 'Offset'
          optional :l, type: Integer, desc: 'Limit'
          optional :q, type: String, desc: 'Query de busca no conteúdo'
        end

        get ':lead_id/messages', http_codes: [
          [401, 'Unauthorized'],
          [404, 'Not Found (Lead not found)'],
          [500, 'Internal Server Error']
        ] do
          response = LeadMessageService.list(params)
          process_service_response(response)
        end
      end

      # POST /api/v1/leads/:lead_id/messages - Criar mensagem
      resource '' do
        desc 'Criar mensagem para o lead' do
          summary 'Criar mensagem para o lead'
          detail 'Cria uma nova mensagem para o lead.'
          success [code: 201, message: 'Created', model: Api::Entities::LeadMessage]
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead (aceita qualquer formato via by_any_id)'
          requires :sender_role, type: String, desc: 'Papel do remetente (user ou agent)'
          requires :content, type: String, desc: 'Conteúdo da mensagem'
          optional :intention, type: String, desc: 'Intenção da mensagem'
          optional :agent_type, type: String, desc: 'Tipo/nome do agente que escreveu a mensagem'
          optional :instruction, type: String, desc: 'Instrução específica relacionada à mensagem'
          optional :group_id, type: Integer, desc: 'ID do grupo (default automático)'
        end

        post ':lead_id/messages', http_codes: [
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found (Lead not found)'],
          [500, 'Internal Server Error']
        ] do
          response = LeadMessageService.create(params)
          process_service_response(response)
        end
      end

      # POST /api/v1/leads/:lead_id/messages/bulk - Criar mensagens em massa
      resource '' do
        desc 'Criar mensagens em massa' do
          summary 'Criar mensagens em massa'
          detail 'Cria múltiplas mensagens para um lead de uma vez.'
          success [code: 201, message: 'Created', model: Api::Entities::LeadMessage]
          is_array true
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead (aceita qualquer formato via by_any_id)'
          optional :group_id, type: Integer, desc: 'ID do grupo (se não informado, gera automaticamente)'
          requires :messages, type: Array, desc: 'Array de mensagens' do
            requires :sender_role, type: String, desc: 'Papel do remetente (user ou agent)'
            optional :agent_type, type: String, desc: 'Tipo/nome do agente que escreveu a mensagem'
            optional :instruction, type: String, desc: 'Instrução específica relacionada à mensagem'
            requires :content, type: String, desc: 'Conteúdo da mensagem'
            optional :intention, type: String, desc: 'Intenção da mensagem'
          end
        end

        post ':lead_id/messages/bulk', http_codes: [
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found (Lead not found)'],
          [500, 'Internal Server Error']
        ] do
          response = LeadMessageService.create_bulk(params)
          process_service_response(response)
        end
      end

      # GET /api/v1/leads/:lead_id/messages/:id - Buscar mensagem específica
      resource '' do
        desc 'Buscar mensagem específica' do
          summary 'Buscar mensagem específica'
          detail 'Retorna os detalhes de uma mensagem específica.'
          success [code: 200, message: 'Ok', model: Api::Entities::LeadMessage]
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead'
          requires :id, type: String, desc: 'ID da mensagem (aceita ID numérico ou smart_id)'
        end

        get ':lead_id/messages/:id', http_codes: [
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          response = LeadMessageService.get_message(params[:id])
          process_service_response(response)
        end
      end

      # DELETE /api/v1/leads/:lead_id/messages/:id - Deletar mensagem
      resource '' do
        desc 'Deletar mensagem' do
          summary 'Deletar mensagem'
          detail 'Remove uma mensagem.'
          success [code: 204, message: 'No Content']
        end

        params do
          requires :lead_id, type: String, desc: 'ID do lead'
          requires :id, type: String, desc: 'ID da mensagem (aceita ID numérico ou smart_id)'
        end

        delete ':lead_id/messages/:id', http_codes: [
          [204, 'No Content'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [500, 'Internal Server Error']
        ] do
          response = LeadMessageService.destroy(params[:id])
          process_service_response(response)
        end
      end
    end
  end
end
