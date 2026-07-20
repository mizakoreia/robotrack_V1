# frozen_string_literal: true

module People
  # workspace-membership §"Resolução de Person no aceite de convite" (tarefa 5.3 / D-10).
  #
  # Dado um workspace e um e-mail, casa com a `Person` existente daquele e-mail no
  # workspace (case-insensitive via citext) ou cria uma nova; preenche `user_id`
  # NA LINHA EXISTENTE quando o convidado tem conta. Preserva a `Person` existente
  # em vez de duplicar — o histórico de atribuições (Ana com 7 tarefas e
  # `user_id NULL`) não se parte: o mesmo `person_id` continua valendo.
  #
  # A RLS escopa a busca ao workspace corrente, então um e-mail que existe em WS-B
  # nunca é reutilizado em WS-A — cria-se uma nova `Person` em WS-A.
  class ResolveService
    def initialize(workspace_id:, email:, name: nil, user_id: nil)
      @workspace_id = workspace_id
      @email = email.presence
      @name = name
      @user_id = user_id
    end

    def call
      Tenant.with(workspace_id: @workspace_id, user_id: @user_id) do
        person = @email && Person.find_by(email: @email)
        person ? attach_user(person) : create_person
      end
    end

    private

    def attach_user(person)
      person.update!(user_id: @user_id) if @user_id && person.user_id.nil?
      person
    end

    def create_person
      Person.create!(name: @name.presence || default_name, email: @email, user_id: @user_id)
    end

    def default_name
      @email.to_s.split('@').first.presence || 'Responsável'
    end
  end
end
