# frozen_string_literal: true

class LeadMessageService
  class << self
    include ApiResponseHandler

    def list(params)
      lead_id = params[:lead_id]
      lead = Lead.by_any_id(lead_id)
      return not_found_response('Lead') unless lead

      offset = params[:o] || 0
      limit = params[:l] || 100
      query = params[:q] || ''

      messages = lead.messages.order(created_at: :desc).offset(offset).limit(limit)
      messages = messages.where('content ILIKE ?', "%#{query}%") if query.present?

      success_response(Api::Entities::LeadMessage.represent(messages).as_json, 200)
    end

    def get_message(id)
      message = LeadMessage.by_any_id(id)
      return not_found_response('Message') unless message

      success_response(Api::Entities::LeadMessage.represent(message).as_json, 200)
    end

    def create(params)
      lead_id = params.delete(:lead_id)
      lead = Lead.by_any_id(lead_id)
      return not_found_response('Lead') unless lead

      begin
        ensure_user_id!(params)
        message = lead.messages.create!(params)

        # Enviar notificação em tempo real para o chat
        broadcast_message_created(message)

        success_response(Api::Entities::LeadMessage.represent(message).as_json, 201)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      end
    end

    def create_bulk(params)
      lead_id = params.delete(:lead_id)
      group_id = params[:group_id]
      messages_data = params[:messages]

      lead = Lead.by_any_id(lead_id)
      return not_found_response('Lead') unless lead

      # Se group_id não foi fornecido, gera um automaticamente
      group_id ||= LeadMessage.generate_bulk_group_id

      created_messages = []

      begin
        LeadMessage.transaction do
          messages_data.each do |message_params|
            ensure_user_id!(message_params)
            message_params = message_params.merge(group_id: group_id)
            message = lead.messages.create!(message_params)
            created_messages << message
          end
        end

        # Enviar notificação em tempo real para mensagens em bulk
        created_messages.each { |message| broadcast_message_created(message) }

        success_response(Api::Entities::LeadMessage.represent(created_messages).as_json, 201)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def update(params)
      id = params.delete(:id)
      message = LeadMessage.by_any_id(id)
      return not_found_response('Message') unless message

      begin
        update_attrs = params.slice(:content, :agent_type, :instruction, :group_id, :content_type, :media_url,
                                    :media_mime, :source_message_id)
        message.update!(update_attrs.compact)
        success_response(Api::Entities::LeadMessage.represent(message).as_json, 200)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      end
    end

    def destroy(id)
      message = LeadMessage.by_any_id(id)
      return not_found_response('Message') unless message

      begin
        message.destroy!
        no_content_response
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    private

    # Método para enviar notificação em tempo real quando mensagem é criada
    def broadcast_message_created(message)
      lead = message.lead

      # Broadcast apenas para o canal específico deste lead
      ActionCable.server.broadcast(
        "lead_chat_#{lead.id}",
        {
          type: 'message_created',
          lead_id: lead.id,
          lead_smart_id: lead.smart_id,
          message_id: message.id,
          sender_role: message.sender_role,
          content_preview: message.content.to_s.truncate(50),
          created_at: message.created_at.iso8601
        }
      )

      Rails.logger.info "📡 Broadcast enviado para lead_chat_#{lead.id}"
    end

    def ensure_user_id!(params)
      return unless params[:sender_role].to_s == 'user'

      params[:user_id] ||= current_user_from_context&.id
    end

    # Helper para obter o usuário atual do contexto (se disponível)
    def current_user_from_context
      # Este método precisa ser implementado baseado em como o contexto
      # do usuário atual é passado para o service
      nil
    end
  end
end
