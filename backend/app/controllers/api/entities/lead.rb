# frozen_string_literal: true

module Api
  module Entities
    class Lead < Grape::Entity
      expose :id, documentation: { type: 'Integer', desc: 'ID do lead' }
      expose :smart_id, documentation: { type: 'String', desc: 'ID inteligente do lead (LD-XXXXXXXXXX)' }
      expose :session_uuid,
             documentation: { type: 'String', desc: 'UUID único da sessão (chave especial para automações)' }
      expose :source_type, documentation: { type: 'String', desc: 'Tipo de origem (whatsapp, instagram, chat)' }
      expose :source_id, documentation: { type: 'String', desc: 'ID da origem' }
      expose :current_stage, documentation: { type: 'String', desc: 'Estágio atual (discovery, enchantment, closing)' }
      expose :last_interaction_at, documentation: { type: 'DateTime', desc: 'Última interação' }

      # Campos do lead
      expose :name, documentation: { type: 'String', desc: 'Nome do lead' }
      expose :phone, documentation: { type: 'String', desc: 'Telefone do lead' }
      expose :ig_username, documentation: { type: 'String', desc: 'Username do Instagram' }
      expose :company_name, documentation: { type: 'String', desc: 'Nome da empresa' }
      expose :has_site, documentation: { type: 'Boolean', desc: 'Se possui site (null até ser perguntado)' }
      expose :site_url, documentation: { type: 'String', desc: 'URL do site' }
      expose :site_scrapped_text, documentation: { type: 'String', desc: 'Texto extraído do site' }
      expose :intention, documentation: { type: 'String', desc: 'Intenção estimada do lead' }

      # Operação associada
      expose :operation_id, documentation: { type: 'Integer', desc: 'ID da operação associada' }, if: lambda { |lead, _|
        lead.respond_to?(:operation_id)
      }
      expose :operation_key, documentation: { type: 'String', desc: 'Chave da operação associada' }, if: lambda { |lead, _|
        lead.respond_to?(:operation_key)
      }

      # Novos campos de categorização
      expose :is_categorized, documentation: { type: 'Boolean', desc: 'Se o lead já foi categorizado explicitamente' }
      expose :content, documentation: { type: 'String', desc: 'Conteúdo da última mensagem recebida/enviada' } do |lead|
        if lead.respond_to?(:content) && lead.has_attribute?(:content)
          lead.content
        elsif lead.respond_to?(:last_message_content) && lead.has_attribute?(:last_message_content)
          lead.last_message_content
        else
          lead.messages.order(created_at: :desc).limit(1).pluck(:content).first
        end
      end
      expose :content_type,
             documentation: { type: 'String',
                              desc: 'Tipo da última mensagem (text, image, audio, video, file, ephemeral)' } do |lead|
        if lead.respond_to?(:content_type) && lead.has_attribute?(:content_type)
          lead.content_type
        elsif lead.respond_to?(:last_message_type) && lead.has_attribute?(:last_message_type)
          lead.last_message_type
        else
          lead.messages.order(created_at: :desc).limit(1).pluck(:content_type).first
        end
      end
      expose :content_id, documentation: { type: 'String', desc: 'ID da mensagem/mídia na fonte original' } do |lead|
        if lead.respond_to?(:content_id) && lead.has_attribute?(:content_id)
          lead.content_id
        else
          lead.messages.order(created_at: :desc).limit(1).pluck(:source_message_id).first
        end
      end
      expose :source_endpoint,
             documentation: { type: 'String',
                              desc: 'Tipo da interação inicial (message, comment, reaction, call)' } do |lead|
        if lead.respond_to?(:source_endpoint) && lead.has_attribute?(:source_endpoint)
          lead.source_endpoint
        else
          'message'
        end
      end
      expose :last_message_sender_role,
             documentation: { type: 'String', desc: 'Remetente da última mensagem (user/agent/admin)' } do |lead|
        lead.messages.order(created_at: :desc).limit(1).pluck(:sender_role).first
      end

      # Campos do sistema Cross-Channel
      expose :unified_from_channels,
             documentation: { type: 'Boolean', desc: 'Indica se o lead foi unificado de múltiplos canais' }
      expose :sources_description, documentation: { type: 'String', desc: 'Descrição das fontes unificadas' }
      expose :all_sources, documentation: { type: 'Array', desc: 'Array com todas as fontes do lead' }

      # IDs sociais e alvo
      expose :igs_id, documentation: { type: 'String', desc: 'ID numérico do Instagram' }, if: lambda { |lead, _|
        lead.respond_to?(:igs_id) && lead.has_attribute?(:igs_id)
      }
      expose :fb_id, documentation: { type: 'String', desc: 'ID numérico do Facebook' }, if: lambda { |lead, _|
        lead.respond_to?(:fb_id) && lead.has_attribute?(:fb_id)
      }
      expose :fb_username, documentation: { type: 'String', desc: 'Username do Facebook' }, if: lambda { |lead, _|
        lead.respond_to?(:fb_username) && lead.has_attribute?(:fb_username)
      }
      expose :target_id, documentation: { type: 'String', desc: 'Identificador da aplicação na fonte de origem' }, if: lambda { |lead, _|
        lead.respond_to?(:target_id) && lead.has_attribute?(:target_id)
      }
      expose :execution_id, documentation: { type: 'String', desc: 'ID da execução/campanha associada' }, if: lambda { |lead, _|
        lead.respond_to?(:execution_id) && lead.has_attribute?(:execution_id)
      }

      # Níveis de progresso
      expose :discovery_level, documentation: { type: 'Integer', desc: 'Nível de descoberta (1-5)' }
      expose :enchantment_level, documentation: { type: 'Integer', desc: 'Nível de encantamento (1-5)' }
      expose :closing_level, documentation: { type: 'Integer', desc: 'Nível de fechamento (1-5)' }
      expose :stage_label, documentation: { type: 'String', desc: 'Rótulo do estágio atual' } do |lead|
        case lead.current_stage
        when 'enchantment' then 'EM EDUCAÇÃO'
        when 'closing' then 'APRESENTAÇÃO'
        else 'DISCOVERY'
        end
      end
      expose :days_since_last_interaction,
             documentation: { type: 'Integer', desc: 'Dias desde a última interação' } do |lead|
        lead.last_interaction_at ? ((Time.current - lead.last_interaction_at) / 1.day).floor : nil
      end

      # Campo de instrução do classificador
      expose :instruction,
             documentation: { type: 'String', desc: 'Comando gerado pelo classificador para outros agentes' }

      # ===============================================
      # CRITÉRIOS DE ENCANTAMENTO - ALGORITMO DE VENDAS
      # Preenchidos pelo agente durante a etapa de encantamento
      # ===============================================
      expose :understands_goals,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente entendeu que o objetivo é criar sites únicos e memoráveis no nicho' }
      expose :understands_smart_navigation,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente compreendeu navegação inteligente e estrutura diferenciada' }
      expose :understands_complexity,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente entendeu diferença entre soluções personalizadas vs genéricas (WordPress)' }
      expose :understands_thats_exclusive,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente compreendeu que terá site exclusivo, não adaptado de template' }
      expose :understands_thats_memorable,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente concordou que sites personalizados são mais memoráveis' }
      expose :likes_some_site,
             documentation: { type: 'String', desc: 'Critério: Cliente demonstrou gostar de algum site do portfólio' }
      expose :likes_some_app,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente demonstrou interesse em app/funcionalidade apresentada' }
      expose :knows_app1_site, documentation: { type: 'String', desc: 'Critério: Cliente viu exemplo de site/app 1' }
      expose :knows_app2_site, documentation: { type: 'String', desc: 'Critério: Cliente viu exemplo de site/app 2' }
      expose :knows_app3_site, documentation: { type: 'String', desc: 'Critério: Cliente viu exemplo de site/app 3' }
      expose :knows_console_mod,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente entendeu que terá painel administrativo para gerenciar conteúdo' }
      expose :knows_whats_mod,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente foi apresentado à integração WhatsApp e possibilidades futuras' }
      expose :knows_own_demand,
             documentation: { type: 'String',
                              desc: 'Critério: Demanda específica identificada e registrada pelo agente' }

      # Contagem de critérios de encantamento completados
      expose :enchantment_criteria_count,
             documentation: { type: 'Integer', desc: 'Número de critérios de encantamento completados (0-13)' }
      expose :enchantment_criteria_questions,
             documentation: { type: 'Hash', desc: 'Perguntas de encantamento' } do |_lead|
        ::Lead.all_enchantment_criteria
      end

      # ===============================================
      # CRITÉRIOS DE FECHAMENTO - ALGORITMO DE VENDAS
      # Preenchidos pelo agente durante a etapa de fechamento
      # ===============================================
      expose :validated_interest,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente demonstrou interesse claro no projeto antes da reunião' }
      expose :understands_value,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente compreendeu o valor da proposta e o que está incluído nos serviços' }
      expose :received_proposal,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente recebeu e acessou o link do orçamento/proposta comercial' }
      expose :gave_feedback,
             documentation: { type: 'String', desc: 'Critério: Cliente forneceu feedback sobre a proposta apresentada' }
      expose :ready_to_schedule,
             documentation: { type: 'String',
                              desc: 'Critério: Cliente demonstrou intenção de avançar e agendar próximos passos' }

      # Contagem de critérios completados
      expose :closing_criteria_count,
             documentation: { type: 'Integer', desc: 'Número de critérios de fechamento completados (0-5)' }
      expose :closing_criteria_questions, documentation: { type: 'Hash', desc: 'Perguntas de fechamento' } do |_lead|
        ::Lead.all_closing_criteria
      end

      # Métricas
      expose :messages_count, documentation: { type: 'Integer', desc: 'Total de mensagens do lead' } do |lead|
        lead.messages.count
      end
      expose :has_unread,
             documentation: { type: 'Boolean', desc: 'Se há mensagem nova não lida (última do usuário)' } do |lead|
        last_role = lead.messages.order(created_at: :desc).limit(1).pluck(:sender_role).first
        last_role == 'user'
      end

      expose :created_at, documentation: { type: 'DateTime', desc: 'Data de criação' }
      expose :updated_at, documentation: { type: 'DateTime', desc: 'Data de atualização' }
    end
  end
end
