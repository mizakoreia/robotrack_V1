# frozen_string_literal: true

module Invitations
  # workspace-invitations §"Pré-visualização pública do convite" (tarefa 3.4 /
  # D-INV-6).
  #
  # Rota PÚBLICA: quem tem o link, mas ainda não autenticou, precisa saber a que
  # workspace foi convidado e com qual papel — senão o fluxo "abre o link → faz
  # login" é um salto no escuro. O que sai é o mínimo: nome do workspace, papel,
  # e-mail MASCARADO, expiração e estado.
  #
  # Nunca sai: e-mail completo (alvo de phishing pronto para quem interceptar o
  # link), `workspace_id` (é o identificador usado em toda a API de domínio),
  # `created_by_person_id` nem qualquer lista.
  class PreviewService
    include ApiResponseHandler

    def initialize(token:)
      @token = token.to_s
    end

    def call
      row = lookup
      return error_response('invitation_not_found', 404) if row.nil?

      invitation = Invitation.new(
        email: row['email'], role: row['role'],
        expires_at: parse_time(row['expires_at']), used_at: parse_time(row['used_at'])
      )

      success_response(
        {
          workspace_name: workspace_name(row['workspace_id']),
          role: invitation.role,
          email_masked: invitation.email_masked,
          expires_at: invitation.expires_at,
          status: invitation.status
        },
        200
      )
    end

    private

    def lookup
      return nil if @token.blank?

      conn = ActiveRecord::Base.connection
      conn.select_one("SELECT * FROM invitation_by_token(#{conn.quote(@token)})")
    end

    # O nome do workspace é lido DENTRO do contexto daquele workspace: a política
    # de `workspaces` libera a linha quando `id = app.current_workspace_id`.
    # Possuir o token é justamente o que autoriza saber para onde ele leva — não
    # há afrouxamento de RLS aqui, só um contexto aberto pelo próprio token.
    def workspace_name(workspace_id)
      Tenant.with(workspace_id: workspace_id, user_id: nil) do
        Workspace.where(id: workspace_id).pick(:name)
      end
    end

    def parse_time(value)
      return value if value.nil? || value.is_a?(Time)

      Time.zone.parse(value.to_s)
    end
  end
end
