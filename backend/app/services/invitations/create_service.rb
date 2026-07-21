# frozen_string_literal: true

module Invitations
  # workspace-invitations §"Criação de convite restrita ao dono" (tarefa 2.3 /
  # invariante 7).
  #
  # Roda DENTRO da transação e do contexto de tenant que `Api::Root` já abriu
  # para as rotas de domínio — por isso não chama `Tenant.with`: abrir outra
  # transação aqui só criaria um savepoint aninhado e um `SET LOCAL` que não é
  # revertido no `RELEASE`.
  #
  # O convite aponta SEMPRE para o workspace corrente. Um `workspace_id` vindo do
  # corpo não é ignorado em silêncio: se divergir, é `403` — ignorar deixaria o
  # chamador crendo que teve sucesso ao redirecionar o convite.
  class CreateService
    include ApiResponseHandler

    ALLOWED_ROLES = %w[view edit].freeze
    EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    def initialize(current_user:, current_role:, workspace_id:, email:, role:, requested_workspace_id: nil)
      @current_user = current_user
      @current_role = current_role
      @workspace_id = workspace_id
      @email = email.to_s.strip.downcase
      @role = role.to_s
      @requested_workspace_id = requested_workspace_id.presence
    end

    def call
      return error_response('forbidden', 403) unless InvitationPolicy.create?(::Authorization::RoleContext.new(@current_role))

      # Invariante 7: o convite é do workspace do criador, ponto. Pedir outro é
      # negado com o mesmo `forbidden` de quem não é dono — nada sobre a
      # existência de WS-B transparece.
      return error_response('forbidden', 403) if @requested_workspace_id && @requested_workspace_id != @workspace_id

      return error_response('invalid_role', 422) unless ALLOWED_ROLES.include?(@role)
      return error_response('invalid_email', 422) unless valid_email?

      invitation = create_invitation
      success_response(payload(invitation), 201)
    rescue ActiveRecord::RecordNotUnique
      # Já existe convite PENDENTE para este e-mail neste workspace (índice único
      # parcial). Dois links vivos para a mesma pessoa deixariam o dono sem saber
      # qual vale e tornariam a revogação uma adivinhação.
      error_response('invitation_already_pending', 409)
    end

    private

    def valid_email?
      @email.present? && @email.length <= Invitation::EMAIL_MAX && @email.match?(EMAIL_FORMAT)
    end

    def create_invitation
      # Savepoint: uma violação de índice único aborta a transação corrente no
      # Postgres. Sem o `requires_new`, o 409 seria devolvido sobre uma transação
      # já envenenada — e qualquer consulta seguinte falharia com
      # "current transaction is aborted".
      ActiveRecord::Base.transaction(requires_new: true) do
        Invitation.create!(
          email: @email,
          role: @role,
          created_by_person: creator_person,
          used_at: nil,
          used_by_user_id: nil
        )
      end
    end

    # A FK composta exige que o criador seja uma `Person` DESTE workspace. O dono
    # ganha a dele no bootstrap (`workspace-tenancy`), mas não assumimos: casamos
    # por usuário, depois por e-mail, e só então criamos.
    def creator_person
      by_user = Person.find_by(user_id: @current_user.id)
      return by_user if by_user

      by_email = @current_user.email.present? ? Person.find_by(email: @current_user.email.downcase) : nil
      if by_email
        by_email.update!(user_id: @current_user.id) if by_email.user_id.nil?
        return by_email
      end

      Person.create!(name: creator_name, email: @current_user.email&.downcase, user_id: @current_user.id)
    end

    def creator_name
      @current_user.display_name.presence || @current_user.email.to_s.split('@').first.presence || 'usuário'
    end

    def payload(invitation)
      { invitation: invitation }
    end
  end
end
