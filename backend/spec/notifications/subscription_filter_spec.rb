# frozen_string_literal: true

require 'rails_helper'

# notification-preferences G2/G5 (D-P3/D-P4/D-P7) — o pipeline honra as
# preferências (mais-específico-vence, seguidor entra, silenciador sai) e o
# `assign` notifica observadores em 3ª pessoa, tudo sem regredir dedup, nunca-o-
# autor, best-effort e RLS.
RSpec.describe 'Notifications preferências (filtro no pipeline)', :tenancy do
  let(:ws) { make_workspace }

  # Mundo com dono-Person, um membro autor, um terceiro (não-responsável), e o
  # galho projeto→célula→robô→tarefa.
  def world
    in_workspace(ws) do
      owner = Person.create!(name: 'Dona', user_id: ws.owner.id)
      author = Person.create!(name: 'Bruno')
      third = Person.create!(name: 'Carla')
      resp = Person.create!(name: 'Ana')
      project = Project.create!(name: 'L', position: 0)
      cell = Cell.create!(project_id: project.id, name: 'C', position: 0)
      robot = Robot.create!(cell_id: cell.id, name: 'R03', application: 'Handling', position: 0)
      task = create_task(robot, desc: 'Ajuste de TCP')
      { owner: owner.id, author: author.id, third: third.id, resp: resp.id,
        project: project.id, cell: cell.id, robot: robot.id, task: task.id }
    end
  end

  def sub(person, level, id, state)
    NotificationSubscription.create!(person_id: person, "scope_#{level}_id" => id, state: state)
  end

  def advance!(w, by:, from: 0, to: 45)
    in_workspace(ws) do
      adv = TaskAdvance.create!(task_id: w[:task], by: by, author_name_snapshot: 'Bruno',
                                from_progress: from, to_progress: to, comment: 'x', legacy: false,
                                recorded_at: Time.current)
      Notifications::CreateService.for_advance(advance_id: adv.id)
    end
  end

  describe 'SubscriptionResolver (mais-específico-vence, D-P3)' do
    it 'follow no robô vence mute no projeto' do
      w = world
      in_workspace(ws) do
        sub(w[:third], :project, w[:project], 'mute')
        sub(w[:third], :robot, w[:robot], 'follow')
        ctx = { project_id: w[:project], cell_id: w[:cell], robot_id: w[:robot], task_id: w[:task] }
        index = Notifications::SubscriptionResolver.load(ctx)
        expect(Notifications::SubscriptionResolver.wants?(w[:third], index, default: false)).to be(true)
      end
    end

    it 'mute no robô vence follow no projeto' do
      w = world
      in_workspace(ws) do
        sub(w[:third], :project, w[:project], 'follow')
        sub(w[:third], :robot, w[:robot], 'mute')
        ctx = { project_id: w[:project], cell_id: w[:cell], robot_id: w[:robot], task_id: w[:task] }
        index = Notifications::SubscriptionResolver.load(ctx)
        expect(Notifications::SubscriptionResolver.wants?(w[:third], index, default: true)).to be(false)
      end
    end

    it 'sem linha usa o default' do
      w = world
      in_workspace(ws) do
        ctx = { project_id: w[:project], cell_id: w[:cell], robot_id: w[:robot], task_id: w[:task] }
        index = Notifications::SubscriptionResolver.load(ctx)
        expect(Notifications::SubscriptionResolver.wants?(w[:third], index, default: true)).to be(true)
        expect(Notifications::SubscriptionResolver.wants?(w[:third], index, default: false)).to be(false)
      end
    end
  end

  describe 'for_advance filtrado (D-P4)' do
    it 'tabela vazia = comportamento de hoje (responsável recebe, dono recebe)' do
      w = world
      in_workspace(ws) { TaskAssignee.create!(task_id: w[:task], person_id: w[:resp], workspace_id: ws.id) }
      advance!(w, by: w[:author])
      in_workspace(ws) do
        recips = Notification.pluck(:recipient_person_id)
        expect(recips).to contain_exactly(w[:resp], w[:owner]) # resp + dono, menos o autor
      end
    end

    it 'seguidor não-responsável e não-autor passa a receber' do
      w = world
      in_workspace(ws) { sub(w[:third], :cell, w[:cell], 'follow') }
      advance!(w, by: w[:author])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:third]).count).to eq(1)
      end
    end

    it 'seguidor que é o autor NÃO se auto-notifica' do
      w = world
      in_workspace(ws) { sub(w[:author], :robot, w[:robot], 'follow') }
      advance!(w, by: w[:author])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:author]).count).to eq(0)
      end
    end

    it 'responsável que silencia o robô deixa de receber' do
      w = world
      in_workspace(ws) do
        TaskAssignee.create!(task_id: w[:task], person_id: w[:resp], workspace_id: ws.id)
        sub(w[:resp], :robot, w[:robot], 'mute')
      end
      advance!(w, by: w[:author])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:resp]).count).to eq(0)
      end
    end

    it 'dono que silencia o projeto deixa de receber (mute sobrepõe owner-tudo, D-P10)' do
      w = world
      in_workspace(ws) { sub(w[:owner], :project, w[:project], 'mute') }
      advance!(w, by: w[:author])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:owner]).count).to eq(0)
      end
    end

    it 'dedup: responsável que também segue a célula recebe uma linha só' do
      w = world
      in_workspace(ws) do
        TaskAssignee.create!(task_id: w[:task], person_id: w[:resp], workspace_id: ws.id)
        sub(w[:resp], :cell, w[:cell], 'follow')
      end
      advance!(w, by: w[:author])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:resp]).count).to eq(1)
      end
    end
  end

  describe 'assign observador (D-P7)' do
    def assign!(w, added:, actor:)
      in_workspace(ws) do
        Notifications::CreateService.for_assign(task_id: w[:task], added: Array(added), actor_person_id: actor,
                                                recorded_at: Time.current)
      end
    end

    it 'atribuído recebe 2ª pessoa e dono recebe 3ª pessoa, ambos type=assign' do
      w = world
      assign!(w, added: [w[:resp]], actor: w[:author])
      in_workspace(ws) do
        assignee_note = Notification.find_by(recipient_person_id: w[:resp])
        owner_note = Notification.find_by(recipient_person_id: w[:owner])
        expect(assignee_note.type).to eq('assign')
        expect(assignee_note.msg).to eq('Bruno atribuiu você à tarefa "Ajuste de TCP" (robô R03 - Handling)')
        expect(owner_note.type).to eq('assign')
        expect(owner_note.msg).to eq('Bruno atribuiu Ana à tarefa "Ajuste de TCP" (robô R03 - Handling)')
      end
    end

    it 'autor da atribuição (mesmo sendo o dono) não recebe observadora' do
      w = world
      assign!(w, added: [w[:resp]], actor: w[:owner])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:owner]).count).to eq(0)
      end
    end

    it 'seguidor com mute no robô não recebe a observadora' do
      w = world
      in_workspace(ws) { sub(w[:third], :robot, w[:robot], 'mute') }
      assign!(w, added: [w[:resp]], actor: w[:author])
      in_workspace(ws) do
        expect(Notification.where(recipient_person_id: w[:third]).count).to eq(0)
      end
    end

    it 'seguidor do projeto recebe a observadora em 3ª pessoa' do
      w = world
      in_workspace(ws) { sub(w[:third], :project, w[:project], 'follow') }
      assign!(w, added: [w[:resp]], actor: w[:author])
      in_workspace(ws) do
        note = Notification.find_by(recipient_person_id: w[:third])
        expect(note.msg).to eq('Bruno atribuiu Ana à tarefa "Ajuste de TCP" (robô R03 - Handling)')
      end
    end
  end
end
