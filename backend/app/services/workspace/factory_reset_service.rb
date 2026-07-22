# frozen_string_literal: true

class Workspace
  # workspace-settings G5 (§3.11, D12, D-RESET, D-RESET-GATE, D-RESET-ROLLBACK) — a
  # ÚNICA operação destrutiva em massa do produto. Volta o CONTEÚDO do workspace ao
  # estado de fábrica, numa transação `SERIALIZABLE`, preservando o que D12 e a
  # imutabilidade exigem.
  #
  # RECONCILIAÇÃO com a tabela D-RESET (ver EXECUCAO — "RETOMADA G5"): a hierarquia é
  # **ARQUIVADA** (`Hierarchy::SoftDeleteService`), não deletada — `task_advances` é
  # imutável (D-IMUT) e trava as tarefas (FK RESTRICT), então `DELETE` era impossível.
  # O usuário vê o workspace vazio; a trilha imutável e a linha do workspace
  # sobrevivem (D12). `audit_logs` ganha 1 entrada e nada é apagado dele.
  #
  # Destinos: hierarquia → ARQUIVADA; `task_templates` → DELETE + re-seed dos 31
  # padrões; convites pendentes → REVOGADOS (o caminho de workspace-invitations é
  # DELETE real, sem `revoked_at`); `people`/`memberships`/`workspaces`/`workspace_
  # backups` → PRESERVADOS. `notifications`/`WorkspaceChannel`/alerta de operação são
  # HANDOFF (as capacidades ainda não existem).
  class FactoryResetService
    include ApiResponseHandler

    RECENT_WINDOW = 15.minutes

    # Liga/desliga o reset por ambiente. Desligada → o endpoint responde 404 (esconde
    # a existência da operação). Default DESLIGADA (opt-in explícito por deploy).
    def self.feature_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('FEATURE_FACTORY_RESET', 'false'))
    end

    def initialize(context:)
      @context = context
    end

    def call(confirmation_phrase:, backup_id:)
      ws = @context.workspace
      # Gate 1 (D-RESET-GATE) — frase idêntica ao nome, strip das bordas, sensível a
      # caixa. Falha → 422, NADA executa, NENHUMA entrada de auditoria.
      return error_response('reset_phrase_mismatch', 422) unless confirmation_phrase.to_s.strip == ws.name

      # Gate 2 — backup recente, completed, do mesmo workspace (RLS), não consumido.
      backup = ::WorkspaceBackup.find_by(id: backup_id)
      return error_response('reset_backup_invalid', 422) unless backup_usable?(backup)

      projects_count = 0
      # Design pedia SERIALIZABLE; impossível aqui: TODO contexto de tenant (o
      # middleware TenantTransaction no request, `Tenant.with` fora dele) JÁ abre a
      # transação externa — o `SET LOCAL` da RLS vive nela — e isolamento não pode
      # ser setado em transação aninhada. Atomicidade vem do savepoint
      # (`requires_new`, o padrão de TaskAdvances::CreateService); o anti-replay
      # REAL é o CAS no `consumed_at` abaixo (row lock, vale em READ COMMITTED).
      ActiveRecord::Base.transaction(requires_new: true) do
        # Re-verifica e CONSUME o backup sob lock (anti-replay do duplo clique). Se
        # outro reset já o consumiu, 0 linhas atualizadas → aborta com 422.
        consumed = ::WorkspaceBackup.where(id: backup.id, consumed_at: nil)
                                    .update_all(consumed_at: Time.current)
        raise BackupAlreadyConsumed if consumed.zero?

        projects = ::Project.all.to_a
        projects_count = projects.size
        projects.each { |project| ::Hierarchy::SoftDeleteService.call(record: project) }

        ::TaskTemplate.delete_all
        ::Workspaces::SeedDefaultTaskTemplatesService.new(workspace_id: ws.id).call

        ::Invitation.pending.delete_all # revogar = DELETE (workspace-invitations)

        # D12/D14 — o registro do reset NA MESMA transação. Se o INSERT falhar,
        # rollback leva tudo junto (D-RESET-ROLLBACK). `audit_logs` NÃO é tocado
        # por DELETE/UPDATE — só INSERT.
        ::AuditLog::RecordService.record!(
          workspace: ws, event: :workspace_reset, by: @context.person,
          payload: { projects_count: projects_count }
        )
      end

      success_response({ projects_count: projects_count }, 200)
    rescue BackupAlreadyConsumed
      error_response('reset_backup_invalid', 422)
    end

    private

    BackupAlreadyConsumed = Class.new(StandardError)

    def backup_usable?(backup)
      return false if backup.nil?

      backup.status == 'completed' &&
        backup.consumed_at.nil? &&
        backup.created_at >= RECENT_WINDOW.ago
    end
  end
end
