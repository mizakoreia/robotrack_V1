# frozen_string_literal: true

module Api
  module Entities
    # Pré-visualização PÚBLICA (D-INV-6): quem tem o token, mas ainda não
    # autenticou, vê apenas isto. Sem e-mail completo, sem `workspace_id`, sem
    # lista de membros — o token é endereçável por qualquer um que o receba.
    class InvitationPreview < Grape::Entity
      expose(:workspace_name) { |inv| inv[:workspace_name] }
      expose(:role)           { |inv| inv[:role] }
      expose(:email_masked)   { |inv| inv[:email_masked] }
      expose(:expires_at)     { |inv| inv[:expires_at] }
      expose(:status)         { |inv| inv[:status] }
    end
  end
end
