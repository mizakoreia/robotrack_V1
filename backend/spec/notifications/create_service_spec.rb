# frozen_string_literal: true

require 'rails_helper'

# in-app-notifications 4.1/4.4 — persistência best-effort e resiliência.
RSpec.describe Notifications::CreateService, :tenancy do
  let(:ws) { make_workspace }

  def build_world
    in_workspace(ws) do
      recipient = Person.create!(name: 'Ana')
      actor = Person.create!(name: 'Bruno')
      project = Project.create!(name: 'L', position: 0)
      cell = Cell.create!(project_id: project.id, name: 'C', position: 0)
      robot = Robot.create!(cell_id: cell.id, name: 'R03', application: 'Handling', position: 0)
      task = create_task(robot, desc: 'Ajuste de TCP')
      { recipient: recipient.id, actor: actor.id, task: task.id }
    end
  end

  describe 'for_assign idempotente (4.1)' do
    it 'reexecutar com os mesmos parâmetros NÃO cria segunda linha' do
      w = build_world
      ra = '2026-07-23T14:03:00Z'
      in_workspace(ws) do
        described_class.for_assign(task_id: w[:task], added: [w[:recipient]], actor_person_id: w[:actor], recorded_at: ra)
        described_class.for_assign(task_id: w[:task], added: [w[:recipient]], actor_person_id: w[:actor], recorded_at: ra)
        expect(Notification.where(type: 'assign').count).to eq(1)
      end
    end

    it 'monta a msg de assign com task e robô' do
      w = build_world
      in_workspace(ws) do
        described_class.for_assign(task_id: w[:task], added: [w[:recipient]], actor_person_id: w[:actor],
                                   recorded_at: Time.current)
        n = Notification.last
        expect(n.msg).to eq('Bruno atribuiu você à tarefa "Ajuste de TCP" (robô R03 - Handling)')
        expect(n.ctx_task_id).to eq(w[:task])
        expect(n.read).to be(false)
      end
    end
  end

  describe 'for_advance (progress)' do
    it 'cria notificação para os responsáveis, menos o autor' do
      w = build_world
      in_workspace(ws) do
        TaskAssignee.create!(task_id: w[:task], person_id: w[:recipient], workspace_id: ws.id)
        advance = TaskAdvance.create!(task_id: w[:task], by: w[:actor], author_name_snapshot: 'Bruno',
                                      from_progress: 0, to_progress: 45, comment: 'Calibrado eixo 6',
                                      legacy: false, recorded_at: Time.current)
        created = described_class.for_advance(advance_id: advance.id)
        expect(created).to eq(1)
        expect(Notification.last.msg).to include('registrou 45% na tarefa "Ajuste de TCP"')
      end
    end

    it 'reset para 0 → nenhuma notificação' do
      w = build_world
      in_workspace(ws) do
        TaskAssignee.create!(task_id: w[:task], person_id: w[:recipient], workspace_id: ws.id)
        advance = TaskAdvance.create!(task_id: w[:task], by: w[:actor], author_name_snapshot: 'Bruno',
                                      from_progress: 45, to_progress: 0, comment: 'reset', legacy: false,
                                      recorded_at: Time.current)
        expect(described_class.for_advance(advance_id: advance.id)).to eq(0)
      end
    end
  end

  describe 'resiliência: falha ao notificar não derruba o save (4.4)' do
    it 'perform_later lançando (Redis fora) é engolido pelo subscriber, sem propagar' do
      w = build_world
      allow(NotifyTaskEventJob).to receive(:perform_later).and_raise(StandardError.new('redis fora'))

      expect do
        ActiveSupport::Notifications.instrument(
          'task.advanced', task_id: w[:task], robot_id: nil, workspace_id: ws.id,
          advance_id: SecureRandom.uuid, to_progress: 45, status: 'em_andamento'
        )
      end.not_to raise_error
    end
  end
end
