# frozen_string_literal: true

require 'securerandom'
require 'ostruct'

# Helpers para specs de tenancy (tag :tenancy). Criar linhas de tenant sob RLS
# exige contexto — estes helpers encapsulam o `Tenant.with` do bootstrap real
# (que só chega no G5) para os specs de G3/G4.
module TenancyHelpers
  # Cria um workspace (e seu dono) abrindo o contexto do próprio id — o WITH CHECK
  # de `workspaces` exige `id = app.current_workspace_id`, e o id gerável pelo
  # cliente (D1) é justamente o que torna isso possível.
  def make_workspace(owner: nil, name: 'Workspace')
    owner ||= create(:user)
    id = SecureRandom.uuid
    Tenant.with(workspace_id: id, user_id: owner.id) do
      Workspace.create!(id: id, name: name, owner_user_id: owner.id)
    end
    OpenStruct.new(id: id, owner: owner)
  end

  # Executa o bloco no contexto de tenant do workspace.
  def in_workspace(workspace, user: nil, &block)
    Tenant.with(workspace_id: workspace.id, user_id: (user || workspace.owner).id, &block)
  end

  # Adiciona `user` como membro (`role`) do workspace, criando a Person dele.
  def add_member(workspace, user, role)
    in_workspace(workspace) do
      person = Person.create!(name: user.name, email: user.email, user_id: user.id)
      Membership.create!(workspace_id: workspace.id, user: user, person: person, role: role)
    end
  end

  # robot-tasks 1.5 — cria uma tarefa válida para `robot`, resolvendo
  # `workspace_id` do próprio robô (sem informá-lo). É o "factory" de §1.5 no
  # idioma do repo: models de tenant não têm FactoryBot factories (o lint
  # genérico roda `create(name)` sem contexto e a RLS o rejeitaria), então a
  # criação de linha de tenant mora em helper, como `make_workspace`/`seed_people`.
  # Pressupõe contexto de tenant já aberto (use dentro de `in_workspace`).
  def create_task(robot, **attrs)
    defaults = { cat: 'A. Hardware', desc: "Tarefa #{SecureRandom.hex(4)}", position: 0 }
    Task.create!(defaults.merge(attrs).merge(robot_id: robot.id, workspace_id: robot.workspace_id))
  end

  # Semeia `count` pessoas no workspace e devolve os ids.
  def seed_people(workspace, count, prefix: 'Pessoa')
    in_workspace(workspace) do
      Array.new(count) do |i|
        Person.create!(name: "#{prefix} #{workspace.id[0, 4]} #{i}").id
      end
    end
  end
end

RSpec.configure do |config|
  config.include TenancyHelpers, :tenancy
end
