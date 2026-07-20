# frozen_string_literal: true

module Api
  module Entities
    class LeadMessage < Grape::Entity
      expose :id, documentation: { type: 'Integer', desc: 'ID da mensagem' }
      expose :lead_id, documentation: { type: 'Integer', desc: 'ID do lead' }
      expose :smart_id, documentation: { type: 'String', desc: 'ID inteligente da mensagem (MSG-XXXXXXXXXX)' }
      expose :sender_role, documentation: { type: 'String', desc: 'Papel do remetente (user, agent, admin)' }
      expose :content, documentation: { type: 'String', desc: 'Conteúdo da mensagem' }
      expose :intention, documentation: { type: 'String', desc: 'Intenção detectada na mensagem' }
      expose :agent_type, documentation: { type: 'String', desc: 'Tipo/nome do agente que escreveu a mensagem' }
      expose :instruction, documentation: { type: 'String', desc: 'Instrução específica relacionada à mensagem' }
      expose :group_id, documentation: { type: 'Integer', desc: 'ID do grupo para mensagens em bulk' }
      expose :user_id, documentation: { type: 'String', desc: 'UUID do usuário (quando sender_role=admin/user)' }
      # Novos campos de multimídia
      expose :content_type,
             documentation: { type: 'String', desc: 'Tipo de conteúdo (text, image, audio, video, file)' }
      expose :media_url, documentation: { type: 'String', desc: 'URL do conteúdo multimídia, se aplicável' }
      expose :media_mime, documentation: { type: 'String', desc: 'Tipo MIME do conteúdo multimídia' }
      expose :source_message_id,
             documentation: { type: 'String', desc: 'ID original da mensagem (wamid, mid, evolution)' }
      # Campo para indicar se é multimídia
      expose :media?, as: :is_media, documentation: { type: 'Boolean', desc: 'Se a mensagem contém mídia' }
      expose :created_at, documentation: { type: 'DateTime', desc: 'Data de criação' }
      expose :updated_at, documentation: { type: 'DateTime', desc: 'Data de atualização' }
    end
  end
end
