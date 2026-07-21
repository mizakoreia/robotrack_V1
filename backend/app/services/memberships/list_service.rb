# frozen_string_literal: true

module Memberships
  # team-access-management §"Painel de equipe" (tarefa 4.4).
  #
  # A lista inclui o DONO, que não tem linha em `memberships` (o papel dele é
  # derivado de `owner_user_id` — Onda 1, invariante 5). Sem ele o painel diria
  # que um workspace recém-criado tem zero membros, o que é falso e confuso.
  # A linha do dono vem com `is_owner: true` e o id da `Person` dele: é o que
  # permite à UI marcá-la como imutável e ao servidor responder
  # `owner_is_immutable`/`cannot_remove_owner` quando alguém tenta mexer nela
  # mesmo assim.
  class ListService
    include ApiResponseHandler

    Row = Struct.new(:id, :person_id, :name, :email, :role, :is_owner, :invitation_id, keyword_init: true)

    def initialize(current_user:, current_role:, workspace_id:)
      @current_user = current_user
      @current_role = current_role
      @workspace_id = workspace_id
    end

    def call
      policy = MembershipPolicy.new(role: @current_role, user: @current_user, workspace_id: @workspace_id)
      return error_response('forbidden', 403) unless policy.index?

      success_response({ members: [owner_row, *member_rows].compact }, 200)
    end

    private

    def owner_row
      owner_user_id = Workspace.where(id: @workspace_id).pick(:owner_user_id)
      return nil if owner_user_id.nil?

      person = Person.find_by(user_id: owner_user_id)
      Row.new(
        id: person&.id || owner_user_id,
        person_id: person&.id,
        name: person&.name || 'Dono do workspace',
        email: person&.email,
        role: 'owner',
        is_owner: true,
        invitation_id: nil
      )
    end

    def member_rows
      people = Person.where(id: Membership.select(:person_id)).index_by(&:id)

      Membership.order(:created_at).map do |membership|
        person = people[membership.person_id]
        Row.new(
          id: membership.id,
          person_id: membership.person_id,
          name: person&.name,
          email: person&.email,
          role: membership.role,
          is_owner: false,
          invitation_id: membership.invitation_id
        )
      end
    end
  end
end
