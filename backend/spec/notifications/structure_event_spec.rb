# frozen_string_literal: true

require 'rails_helper'

# notification-preferences G6 (§D-P8) — eventos ESTRUTURAIS (criar/excluir
# projeto/célula/robô/tarefa). Destinatários = dono + seguidores do galho −
# autor, honrando `mute`; texto materializado por destinatário (locale). O
# disparo é pós-commit — um create que nem chega a criar não instrumenta nada.
RSpec.describe 'Notifications eventos estruturais (G6)', :tenancy do
  let(:ws) { make_workspace }

  # Dono-Person, um autor colaborador, um terceiro, e o galho completo.
  def world
    in_workspace(ws) do
      owner = Person.create!(name: 'Dona', user_id: ws.owner.id)
      author = Person.create!(name: 'Bruno')
      third = Person.create!(name: 'Carla')
      project = Project.create!(name: 'L', position: 0)
      cell = Cell.create!(project_id: project.id, name: 'C', position: 0)
      robot = Robot.create!(cell_id: cell.id, name: 'R03', application: 'Handling', position: 0)
      task = create_task(robot, desc: 'Ajuste de TCP')
      { owner: owner.id, author: author.id, third: third.id,
        project: project.id, cell: cell.id, robot: robot.id, task: task.id }
    end
  end

  def sub(person, level, id, state)
    NotificationSubscription.create!(person_id: person, "scope_#{level}_id" => id, state: state)
  end

  def robot_ctx(w)     = { project_id: w[:project], cell_id: w[:cell], robot_id: w[:robot] }
  def cell_ctx(w)      = { project_id: w[:project], cell_id: w[:cell] }
  def project_ctx(w)   = { project_id: w[:project] }

  def delete_robot!(w, by:)
    in_workspace(ws) do
      Notifications::CreateService.for_structure(
        workspace_id: ws.id, actor_person_id: by, author: 'Bruno',
        entity: 'robot', action: 'deleted', label: 'R03 - Handling', parent: 'C', ctx: robot_ctx(w)
      )
    end
  end

  describe 'destinatários (§D-P8)' do
    it 'o dono recebe a exclusão de robô feita por um colaborador' do
      w = world
      delete_robot!(w, by: w[:author])
      in_workspace(ws) do
        note = Notification.find_by(recipient_person_id: w[:owner])
        expect(note.type).to eq('structure')
        expect(note.msg).to eq('Bruno removeu o robô "R03 - Handling" da célula "C"')
        expect(note.ctx_robot_id).to eq(w[:robot])
        expect(note.ctx_project_id).to eq(w[:project])
      end
    end

    it 'o galho silenciado pelo dono não gera notificação (mute no projeto, criar célula dentro)' do
      w = world
      in_workspace(ws) { sub(w[:owner], :project, w[:project], 'mute') }
      in_workspace(ws) do
        Notifications::CreateService.for_structure(
          workspace_id: ws.id, actor_person_id: w[:author], author: 'Bruno',
          entity: 'cell', action: 'created', label: 'C2', parent: 'L', ctx: cell_ctx(w)
        )
      end
      in_workspace(ws) { expect(Notification.where(recipient_person_id: w[:owner]).count).to eq(0) }
    end

    it 'o autor da mudança (mesmo sendo o dono) não se notifica' do
      w = world
      delete_robot!(w, by: w[:owner])
      in_workspace(ws) { expect(Notification.where(recipient_person_id: w[:owner]).count).to eq(0) }
    end

    it 'um seguidor não-dono do galho recebe' do
      w = world
      in_workspace(ws) { sub(w[:third], :cell, w[:cell], 'follow') }
      delete_robot!(w, by: w[:author])
      in_workspace(ws) { expect(Notification.where(recipient_person_id: w[:third]).count).to eq(1) }
    end
  end

  describe 'mensagem por locale (D-I5a — congela no idioma do destinatário)' do
    it 'o dono en-US recebe o texto em inglês' do
      w = world
      in_workspace(ws) do
        User.where(id: ws.owner.id).update_all(locale: 'en') # rubocop:disable Rails/SkipsModelValidations
      end
      delete_robot!(w, by: w[:author])
      in_workspace(ws) do
        expect(Notification.find_by(recipient_person_id: w[:owner]).msg)
          .to eq('Bruno removed robot "R03 - Handling" from cell "C"')
      end
    end
  end

  describe 'disparo pós-commit (rollback não enfileira, §D-P8)' do
    def capture(name)
      events = []
      handler = ActiveSupport::Notifications.subscribe(name) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args).payload
      end
      yield
      events
    ensure
      ActiveSupport::Notifications.unsubscribe(handler)
    end

    it 'create bem-sucedido instrumenta structure.changed; validação que falha não instrumenta' do
      world
      in_workspace(ws) do
        Person.create!(name: 'Dona2', user_id: ws.owner.id) unless Person.exists?(user_id: ws.owner.id)
        cell = Cell.first
        ctx = Authorization::Context.new(user: ws.owner, workspace: ws)
        svc = Hierarchy::RobotsService.new(context: ctx)

        ok = capture('structure.changed') do
          svc.create(id: SecureRandom.uuid, name: 'R09', parent_id: cell.id, extra: { application: 'Handling' })
        end
        expect(ok.size).to eq(1)
        expect(ok.first[:entity]).to eq('robot')
        expect(ok.first[:action]).to eq('created')

        bad = capture('structure.changed') do
          svc.create(id: SecureRandom.uuid, name: '', parent_id: cell.id) # nome inválido → 422, não cria
        end
        expect(bad).to be_empty
      end
    end
  end

  describe 'grep-guard das strings estruturais (2.3 / D-P8)' do
    it 'os verbos estruturais não aparecem fora de config/locales e de specs' do
      root = Rails.root
      ['criou o projeto', 'removeu o robô'].each do |fragment|
        offenders = Dir.glob(root.join('{app,lib,config}/**/*.rb')).select { |f| File.read(f).include?(fragment) }
        expect(offenders).to be_empty, "string estrutural fora do locale (#{fragment}): #{offenders.join(', ')}"
      end
    end
  end
end
