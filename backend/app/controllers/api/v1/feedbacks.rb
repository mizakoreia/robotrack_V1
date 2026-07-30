# frozen_string_literal: true

module Api
  module V1
    # send-feedback — canal de feedback do beta. Rota de DOMÍNIO (X-Workspace-Id,
    # RLS): o feedback pertence ao workspace corrente.
    #
    # POST: qualquer MEMBRO envia (`submit_feedback`). O corpo traz só a MENSAGEM e
    # o CONTEXTO automático (rota/workspace/papel/user-agent capturados pelo cliente);
    # `workspace_id` vem do contexto de tenant (nunca do corpo) e `user_id` do bearer.
    # GET: só o DONO lê (`read_feedbacks`) — a caixa do próprio workspace, recentes
    # primeiro.
    class Feedbacks < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      # Teto do pacote de contexto: o campo é livre (o cliente decide o que capturar),
      # então limitamos o tamanho serializado para não virar vetor de abuso. A
      # mensagem já tem CHECK de 1..4000 no banco.
      CONTEXT_MAX_BYTES = 16_000

      resource :feedbacks do
        route_setting :policy, policy: 'FeedbackPolicy', action: :index
        get do
          scope = ::Feedback.includes(:user).order(created_at: :desc)
          present scope, with: Api::Entities::Feedback
        end

        route_setting :policy, policy: 'FeedbackPolicy', action: :create
        params do
          requires :message, type: String, allow_blank: false
          optional :context, type: Hash, default: {}
        end
        post do
          context = params[:context] || {}
          if context.to_json.bytesize > CONTEXT_MAX_BYTES
            error!({ error: 'context_too_large' }, 422)
          end

          feedback = ::Feedback.new(
            message: params[:message].to_s.strip,
            context: context,
            user_id: ::Current.user_id
          )
          feedback.save!
          status 201
          present feedback, with: Api::Entities::Feedback
        rescue ActiveRecord::RecordInvalid => e
          error!({ error: 'invalid', detail: e.record.errors.full_messages }, 422)
        end
      end
    end
  end
end
