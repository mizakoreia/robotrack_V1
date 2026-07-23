# frozen_string_literal: true

require 'rails_helper'

# legacy-data-migration 2.5 (D-LDM-6) — a prova da rede fina: importa (simulado),
# cria dado POR FORA do run (pós-corte), faz rollback e afirma que SÓ o dado do run
# sumiu e que a auditoria cresceu em exatamente 1 entrada. O modo de falha que isto
# guarda é o rollback apagar dado de produção criado depois do corte.
#
# RECONCILIAÇÃO (G2): a hierarquia do run é ARQUIVADA (deleted_at), não deletada —
# `task_advances` é imutável (D-IMUT) e trava as tarefas por FK RESTRICT, o mesmo muro
# do factory-reset. "Restante" = VISÍVEL (deleted_at IS NULL). As folhas sem trava
# (task_assignees, notifications, people) são deletadas de fato.
RSpec.describe 'legacy:rollback — desfaz um run e só ele', :tenancy, type: :model do
  # Monta um "run" à mão (o importador real chega em G4/G5): hierarquia + folhas +
  # 1 avanço legado, tudo mapeado em legacy_id_map; e dado pós-corte NÃO mapeado.
  def seed_run(ws)
    in_workspace(ws) do
      run = LegacyImportRun.create!(
        workspace_id: ws.id, legacy_owner_uid: 'u-dono',
        file_sha256: 'a' * 64, status: 'completed'
      )

      project = create_project(ws, name: 'Linha Importada', position: 0)
      cell    = create_cell(project, name: 'Célula Importada', position: 0)
      robot1  = create_robot(cell, name: 'R-imp-1', position: 0)
      robot2  = create_robot(cell, name: 'R-imp-2', position: 1)
      task1   = create_task(robot1, desc: 'Tarefa com avanço', position: 0)
      task2   = create_task(robot1, desc: 'Tarefa com responsável', position: 1)

      # Avanço legado (by NULL, legacy true) — é ele que travaria o DELETE físico.
      TaskAdvance.create!(
        task: task1, by: nil, author_name_snapshot: 'Ana Lima', legacy: true,
        from_progress: 0, to_progress: 40, comment: nil, recorded_at: 2.days.ago
      )

      person   = Person.create!(name: 'Pessoa Importada')
      assignee = TaskAssignee.create!(task_id: task2.id, person_id: person.id)
      notif    = Notification.create!(
        workspace_id: ws.id,
        recipient_person_id: person.id, actor_person_id: person.id,
        type: 'assign', read: false, msg: 'importada', recorded_at: 1.day.ago,
        author_name_snapshot: 'Pessoa Importada', ts_local: '01/01/2024 00:00'
      )

      map = {
        'project' => project.id, 'cell' => cell.id,
        'robot' => [robot1.id, robot2.id], 'task' => [task1.id, task2.id],
        'person' => person.id, 'task_assignee' => assignee.id, 'notification' => notif.id
      }
      map.each do |type, ids|
        Array(ids).each_with_index do |new_id, i|
          LegacyIdMap.create!(run_id: run.id, entity_type: type,
                              legacy_path: "#{type}[#{i}]", new_id: new_id)
        end
      end

      { run: run, project: project, cell: cell, task1: task1 }
    end
  end

  # Dado criado DEPOIS do corte, por fora do run — não pode ser tocado.
  def seed_post_cut(ws, cell)
    in_workspace(ws) do
      {
        project: create_project(ws, name: 'Linha Pós-Corte', position: 1),
        robot: create_robot(cell, name: 'R-pos-corte', position: 2),
        person: Person.create!(name: 'Pessoa Pós-Corte')
      }
    end
  end

  it 'arquiva a hierarquia do run, deleta as folhas do run e preserva o dado pós-corte' do
    ws = make_workspace(name: 'WS Rollback')
    seeded = seed_run(ws)
    post   = seed_post_cut(ws, seeded[:cell])

    audit_before = in_workspace(ws) { AuditLog.count }

    Legacy::RollbackService.call(run: seeded[:run])

    in_workspace(ws) do
      # Hierarquia do run: fora da visão (arquivada), mas a linha existe.
      expect(Project.where(id: seeded[:project].id)).to be_empty
      expect(Project.unscoped.where(id: seeded[:project].id).first.deleted_at).to be_present
      expect(Robot.where(name: %w[R-imp-1 R-imp-2])).to be_empty
      expect(Task.where(robot_id: seeded[:task1].robot_id)).to be_empty

      # Folhas do run: deletadas de fato.
      expect(TaskAssignee.count).to eq(0)
      expect(Notification.count).to eq(0)
      expect(Person.where(name: 'Pessoa Importada')).to be_empty

      # Avanço legado: IMUTÁVEL, intocado (não é apagado nem trava o rollback).
      expect(TaskAdvance.count).to eq(1)

      # Dado pós-corte: TODO preservado e visível.
      expect(Project.where(id: post[:project].id)).to be_present
      expect(Robot.where(id: post[:robot].id)).to be_present
      expect(Person.where(id: post[:person].id)).to be_present

      # Auditoria: +1, e é a entrada de rollback.
      expect(AuditLog.count).to eq(audit_before + 1)
      expect(AuditLog.order(:ts).last.event_type).to eq('legacy_rollback')

      # O run é marcado como revertido (leitura sob contexto de tenant, RLS).
      expect(LegacyImportRun.find(seeded[:run].id).status).to eq('rolled_back')
    end
  end
end
