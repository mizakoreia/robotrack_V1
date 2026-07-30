# frozen_string_literal: true

module Api
  module Entities
    # send-feedback — a leitura do dono. Expõe a mensagem, o contexto automático e
    # QUEM enviou (nome/e-mail do autor, quando ainda existe). O autor é derivado da
    # FK global `users`; se o usuário foi removido, `submitter` vem nulo (o feedback
    # sobrevive — ON DELETE SET NULL).
    class Feedback < Grape::Entity
      expose :id
      expose :message
      expose :context
      expose :created_at

      expose :submitter do |feedback, _opts|
        user = feedback.user
        next nil unless user

        { name: user.name, email: user.email }
      end
    end
  end
end
