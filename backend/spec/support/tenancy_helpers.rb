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

  # quality-and-accessibility 1.2 — headers de REQUEST autenticados como membro do
  # workspace com o papel dado, JÁ com o `X-Workspace-Id`. Une autenticação e
  # contexto de tenant num lugar só: a RLS é aberta pela própria requisição (o
  # middleware de tenant lê o header), então autenticar sem endereçar o workspace
  # devolve lista vazia e o spec "passa" por engano (D2). `role: 'owner'` reusa o
  # dono; os demais papéis criam um usuário e o adicionam como membership.
  # Precisa de `bearer_headers` (RequestAuthHelper) — use em specs `type: :request`.
  def as_member_of(workspace, role: 'edit', user: nil)
    member =
      if role.to_s == 'owner'
        workspace.owner
      else
        u = user || create(:user)
        add_member(workspace, u, role.to_s)
        u
      end
    bearer_headers(member).merge('X-Workspace-Id' => workspace.id)
  end

  # "Factories" de tenant no idioma de `create_task`: pressupõem contexto aberto
  # (use dentro de `in_workspace`) e resolvem `workspace_id` pelo PAI, para os
  # specs não repetirem a resolução e errarem em um deles (§1.1/D2).
  def create_project(workspace, **attrs)
    ws_id = workspace.respond_to?(:id) ? workspace.id : workspace
    Project.create!({ name: "Projeto #{SecureRandom.hex(4)}", position: 0 }.merge(attrs).merge(workspace_id: ws_id))
  end

  def create_cell(project, **attrs)
    Cell.create!({ name: "Célula #{SecureRandom.hex(4)}", position: 0 }
      .merge(attrs).merge(project_id: project.id, workspace_id: project.workspace_id))
  end

  def create_robot(cell, **attrs)
    Robot.create!({ name: "Robô #{SecureRandom.hex(4)}", application: 'Handling', position: 0 }
      .merge(attrs).merge(cell_id: cell.id, workspace_id: cell.workspace_id))
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
