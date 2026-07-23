# frozen_string_literal: true

module Legacy
  # legacy-data-migration 2.4 (D-LDM-6, D12) — a rede de segurança FINA: desfaz
  # EXATAMENTE o que um run criou, e só isso (registros criados por usuários depois do
  # corte não são tocados), gravando o próprio rollback na auditoria.
  #
  # RECONCILIAÇÃO com progress-advances/audit-log (documentada no EXECUCAO — G2): o
  # design (D-LDM-6) fala em "apagar em ordem inversa de dependência", mas o porte real
  # tem DUAS tabelas APPEND-ONLY imutáveis por REVOKE+trigger — `task_advances` (D-IMUT)
  # e `audit_logs` (D12). Uma tarefa importada com avanço legado é travada pela FK
  # RESTRICT do avanço; o `DELETE` físico é impossível (é o mesmo muro que fez o
  # factory-reset ARQUIVAR em vez de deletar). Logo o rollback:
  #   - a HIERARQUIA do run (projects/cells/robots/tasks) é ARQUIVADA (`deleted_at`),
  #     via os mesmos carimbos do `Hierarchy::SoftDeleteService` — mas SÓ os ids
  #     mapeados, não a subárvore viva (um filho pós-corte sob um nó importado sobrevive).
  #   - as FOLHAS sem trava de imutabilidade (task_assignees, notifications,
  #     task_templates, memberships, people) são DELETADAS de fato, por id mapeado.
  #   - `task_advances`/`audit_logs` importados NÃO são tocados (imutáveis; carregam
  #     marcação de origem legada — um 2º import não os confunde com atividade real).
  #   - UMA entrada `legacy_rollback` é gravada em `audit_logs`.
  # "N robôs restantes" passa a significar N VISÍVEIS (`deleted_at IS NULL`), que é o
  # que o app e as views de progresso contam.
  module RollbackService
    module_function

    # run: o LegacyImportRun a reverter. Roda tudo numa transação (a do Tenant.with):
    # se o INSERT da auditoria falhar, o rollback inteiro reverte (D-RESET-ROLLBACK).
    def call(run:)
      report = { archived: Hash.new(0), deleted: Hash.new(0), skipped: Hash.new(0) }

      Tenant.with(workspace_id: run.workspace_id, user_id: nil) do
        ids = ids_by_entity(run)

        archive_hierarchy(ids, report)
        delete_leaves(ids, report)
        record_audit(run, report)

        run.update!(
          status: 'rolled_back',
          report: run.report.merge('rollback' => stringify(report))
        )
      end

      report
    end

    # Todos os new_id do run, por entity_type (escopado ao workspace pela RLS).
    def ids_by_entity(run)
      LegacyIdMap.where(run_id: run.id)
                 .group_by(&:entity_type)
                 .transform_values { |rows| rows.map(&:new_id) }
    end

    # Hierarquia: ARQUIVA (deleted_at) só os ids mapeados, filhos → pais. `lock_version`
    # explícito (Arel.sql) para o Rails 8 NÃO o incrementar — arquivar não é edição
    # (mesmo padrão do SoftDeleteService).
    def archive_hierarchy(ids, report)
      now = Time.current
      keep = Arel.sql('lock_version')

      task_ids = ids['task'] || []
      if task_ids.any?
        ::TaskAssignee.where(task_id: task_ids).delete_all
        report[:archived]['task'] += ::Task.where(id: task_ids)
                                            .update_all(deleted_at: now, lock_version: keep)
      end

      { 'robot' => ::Robot, 'cell' => ::Cell, 'project' => ::Project }.each do |type, klass|
        node_ids = ids[type] || []
        next if node_ids.empty?

        report[:archived][type] += klass.where(id: node_ids)
                                        .update_all(deleted_at: now, position: nil, lock_version: keep)
      end
    end

    # Folhas hard-deletáveis, por id mapeado. `people` por último (memberships as
    # referenciam) e uma a uma: uma Person importada que virou autora de um avanço
    # REAL pós-corte é travada por FK RESTRICT — nesse caso PULA e reporta, sem
    # abortar o run inteiro.
    def delete_leaves(ids, report)
      simple = { 'task_assignee' => ::TaskAssignee, 'notification' => ::Notification,
                 'task_template' => ::TaskTemplate, 'membership' => ::Membership }
      simple.each do |type, klass|
        row_ids = ids[type] || []
        report[:deleted][type] += klass.where(id: row_ids).delete_all if row_ids.any?
      end

      (ids['person'] || []).each do |pid|
        ::Person.where(id: pid).delete_all
        report[:deleted]['person'] += 1
      rescue ActiveRecord::InvalidForeignKey
        report[:skipped]['person'] += 1
      end
    end

    # 1 entrada de auditoria (evento legacy_rollback). by: nil / by_name literal (a
    # operação é do sistema, não de uma Person). Mesma transação: auditoria e desfazer
    # commitam juntos ou nada (D12/D-RESET-ROLLBACK).
    def record_audit(run, report)
      workspace = ::Workspace.find(run.workspace_id)
      ::AuditLog::RecordService.record!(
        workspace: workspace, event: :legacy_rollback, by: nil,
        payload: {
          by_name: 'Rollback de import legado',
          run_id: run.id,
          projects_count: report[:archived]['project']
        }
      )
    end

    def stringify(report)
      report.transform_values { |h| h.transform_keys(&:to_s) }
    end
  end
end
