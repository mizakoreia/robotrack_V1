# frozen_string_literal: true

module People
  # workspace-settings 2.2 (§3.9, D-PERSON-DEL) — remover um chip é ARQUIVAR, nunca
  # DELETE: `task_advances` (append-only) e `audit_logs` carregam o snapshot do nome
  # e a trilha é imutável. Passos:
  #   1. `archived_at = now()` (some dos seletores/chips ativos);
  #   2. apaga `task_assignees` (atribuições abertas caem — não aparece mais como
  #      responsável em tarefas vivas);
  #   3. `task_advances`/`audit_logs` INTOCADOS.
  # Pessoa com membership ATIVA → 409 (remover quem tem conta é remoção de MEMBRO,
  # de workspace-invitations). A trigger do banco é a rede; aqui a mensagem amigável.
  class ArchiveService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(person_id:)
      person = ::Person.find_by(id: person_id)
      return error_response('not_found', 404) if person.nil?
      return error_response('person_has_membership', 409) if ::Membership.where(person_id: person.id).exists?

      ActiveRecord::Base.transaction do
        ::TaskAssignee.where(person_id: person.id).delete_all
        person.update!(archived_at: Time.current)
      end
      success_response({ id: person.id }, 200)
    rescue ActiveRecord::StatementInvalid => e
      # corrida: membership criada entre a checagem e o UPDATE → a trigger barra.
      raise unless e.message.include?('membership ativa')

      error_response('person_has_membership', 409)
    end
  end
end
