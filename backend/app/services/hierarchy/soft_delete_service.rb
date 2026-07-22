# frozen_string_literal: true

module Hierarchy
  # hierarchy-soft-delete G2 (§2.9, D3) — o CASCADE de soft-delete da hierarquia.
  #
  # Sem DELETE físico, o `ON DELETE CASCADE` das FKs não dispara: o cascade vira
  # trabalho de aplicação. Arquiva a subárvore de BAIXO para cima numa transação —
  # tarefas → robôs → células → o nó — com um `UPDATE em massa` por nível (não N
  # callbacks), espelhando o espírito do D-H6 ("um DELETE, não 200 callbacks").
  #
  # As tarefas são arquivadas como `Tasks::DeleteService` já faz para uma só:
  # `deleted_at` carimbado e os `task_assignees` REMOVIDOS (o CASCADE só existiria
  # num hard delete; sem ele, um chip órfão sobraria em "Minhas Tarefas").
  #
  # `position` dos nós de hierarquia vai a `NULL` (D1 — sai do domínio da constraint
  # DEFERRABLE de posição, para a renumeração dos irmãos vivos nunca colidir). O
  # `lock_version` é passado explícito (`Arel.sql('lock_version')`) para o Rails 8
  # NÃO o incrementar: arquivar não é edição de conteúdo (mesmo motivo de
  # `ReorderService`).
  #
  # Todas as consultas partem de relações ESCOPADAS (default_scope: só vivos), então
  # reexecutar sobre uma subárvore parcialmente arquivada não reescreve o carimbo de
  # quem já estava arquivado. Roda dentro da transação do chamador (`CrudService`),
  # mas abre a sua própria para poder ser reusada isolada (ex.: o reset por projeto).
  module SoftDeleteService
    module_function

    # Arquiva `record` (Project/Cell/Robot) e toda a subárvore viva abaixo dele.
    def call(record:)
      now = Time.current

      project_ids = []
      cell_ids    = []
      robot_ids   = []

      case record
      when ::Project
        project_ids = [record.id]
        cell_ids    = ::Cell.where(project_id: record.id).pluck(:id)
        robot_ids   = ::Robot.where(cell_id: cell_ids).pluck(:id) if cell_ids.any?
      when ::Cell
        cell_ids  = [record.id]
        robot_ids = ::Robot.where(cell_id: record.id).pluck(:id)
      when ::Robot
        robot_ids = [record.id]
      else
        raise ArgumentError, "soft-delete não suportado para #{record.class}"
      end

      task_ids = robot_ids.any? ? ::Task.where(robot_id: robot_ids).pluck(:id) : []

      ActiveRecord::Base.transaction do
        if task_ids.any?
          ::TaskAssignee.where(task_id: task_ids).delete_all
          ::Task.where(id: task_ids).update_all(deleted_at: now, lock_version: Arel.sql('lock_version'))
        end
        archive_nodes(::Robot, robot_ids, now)
        archive_nodes(::Cell, cell_ids, now)
        archive_nodes(::Project, project_ids, now)
      end
    end

    # Um UPDATE por nível: `deleted_at` + `position = NULL`, sem bump de lock_version.
    def archive_nodes(klass, ids, now)
      return if ids.empty?

      klass.where(id: ids).update_all(
        deleted_at: now, position: nil, lock_version: Arel.sql('lock_version')
      )
    end
  end
end
