# frozen_string_literal: true

require 'rails_helper'

# my-tasks-view §4/§5 (§3.6, §2.2, §2.3, D2/D10/D-MTV-3/4) — as provas de
# comportamento da consulta e o isolamento de tenant. A consulta única de
# `MyTasks::ListService` tem de: mostrar só as ABERTAS do viewer, uma vez cada,
# excluir N/A por STATUS (não por progresso), sumir a tarefa concluída pelo fluxo
# real de avanço, e NUNCA cruzar workspaces (RLS é o backstop).
RSpec.describe 'my-tasks-view — comportamento e isolamento', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  let(:viewer) { in_workspace(ws) { Person.find_by(user_id: owner.id) || Person.create!(name: 'Ana', user_id: owner.id) } }

  # Um robô "vazio" reutilizável e um contador de posição para não colidir nos
  # índices únicos de position.
  def robot!(name: 'R')
    @pos = (@pos || -1) + 1
    in_workspace(ws) do
      p = Project.create!(name: "P#{@pos}", position: @pos)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      Robot.create!(cell_id: c.id, name: name, application: 'Solda Ponto', position: 0)
    end
  end

  def assign!(task, person)
    in_workspace(ws) { TaskAssignee.create!(task_id: task.id, person_id: person.id, workspace_id: ws.id) }
  end

  def list(person = viewer)
    in_workspace(ws) do
      MyTasks::ListService.new.call(workspace_id: ws.id, person_id: person.id)[:data][:rows]
    end
  end

  def context_for(user)
    in_workspace(ws) { Authorization::Context.new(user: user, workspace: Workspace.find(ws.id)) }
  end

  def advance!(task, to:, actor:, comment: 'ok', lock_version: 0)
    in_workspace(ws) do
      TaskAdvances::CreateService.new(context: context_for(actor)).call(
        task_id: task.id, id: SecureRandom.uuid, progress: to, comment: comment, lock_version: lock_version
      )
    end
  end

  # 4.1 — caminho feliz: os 6 campos das colunas.
  it '4.1 tarefa in_progress (45) do viewer aparece com os campos das colunas' do
    r = robot!
    task = in_workspace(ws) { create_task(r, desc: 'Fixar base', position: 0, status: 'Em Andamento', progress: 45) }
    assign!(task, viewer)

    row = list.first
    expect(row).to include(
      'description' => 'Fixar base', 'status' => 'Em Andamento', 'progress' => 45,
      'robot_name' => 'R'
    )
    expect(row['project_name']).to be_present
    expect(row['cell_name']).to eq('C')
  end

  # 4.2 — some da lista quando vai a Concluído pelo fluxo REAL de avanço (§2.2).
  it '4.2 avanço 45→100 leva a Concluído e a tarefa some da lista' do
    r = robot!
    task = in_workspace(ws) { create_task(r, desc: 'T', position: 0, status: 'Em Andamento', progress: 45) }
    assign!(task, viewer)
    expect(list.size).to eq(1)

    res = advance!(task, to: 100, actor: owner)
    expect(res[:status]).to eq(201)
    expect(list).to be_empty # filtro por STATUS no servidor, não no cliente
  end

  # 4.3 — exclusão por STATUS, não por progresso.
  it '4.3 N/A não aparece; Pendente com progresso 0 aparece' do
    r = robot!
    na = in_workspace(ws) { create_task(r, desc: 'NA', position: 0, status: 'N/A', progress: 0) }
    pend = in_workspace(ws) { create_task(r, desc: 'Pend', position: 1, status: 'Pendente', progress: 0) }
    assign!(na, viewer)
    assign!(pend, viewer)

    descs = list.map { |x| x['description'] }
    expect(descs).to eq(['Pend'])
  end

  # 4.4 — só do viewer, e uma vez mesmo com vários responsáveis.
  it '4.4 tarefa de outra pessoa não aparece; multi-responsável aparece 1x' do
    r = robot!
    outra = in_workspace(ws) { Person.create!(name: 'Bruno') }
    so_do_outro = in_workspace(ws) { create_task(r, desc: 'SoBruno', position: 0, status: 'Em Andamento', progress: 10) }
    compartilhada = in_workspace(ws) { create_task(r, desc: 'Compart', position: 1, status: 'Em Andamento', progress: 10) }
    terceiro = in_workspace(ws) { Person.create!(name: 'Caio') }

    assign!(so_do_outro, outra)
    [viewer, outra, terceiro].each { |p| assign!(compartilhada, p) }

    descs = list.map { |x| x['description'] }
    expect(descs).to eq(['Compart']) # SoBruno não; Compart exatamente uma vez
  end

  # 4.5 — Person sem user_id como único responsável: não aparece p/ ninguém.
  it '4.5 tarefa cujo único responsável é Person sem user_id não aparece nem para o dono' do
    r = robot!
    sem_conta = in_workspace(ws) { Person.create!(name: 'Chão de Fábrica', user_id: nil) }
    task = in_workspace(ws) { create_task(r, desc: 'Só do sem-conta', position: 0, status: 'Em Andamento', progress: 20) }
    assign!(task, sem_conta)

    expect(list(viewer)).to be_empty
    # continua atribuída (aparece nos chips da tela do robô — task_assignees intacto)
    expect(in_workspace(ws) { TaskAssignee.where(task_id: task.id).count }).to eq(1)
  end

  # 4.6 — e2e SEM factory de Person: bootstrap real + auto-atribuição (§2.3).
  it '4.6 bootstrap real, tarefa sem responsável, avanço 0→20 auto-atribui e vira 1 linha', :aggregate_failures do
    novo = create(:user, name: 'Novo Dono', email: 'novo@fabrica.com')
    w = Workspaces::BootstrapService.new(user: novo).call # cria a Person do dono

    task = Tenant.with(workspace_id: w.id, user_id: novo.id) do
      p = Project.create!(name: 'P', position: 0)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
      create_task(r, desc: 'Sem responsável', position: 0, status: 'Pendente', progress: 0)
    end

    # avanço 0→20 pelo dono: §2.3 auto-atribui o autor (a tarefa não tinha responsável)
    Tenant.with(workspace_id: w.id, user_id: novo.id) do
      ctx = Authorization::Context.new(user: novo, workspace: Workspace.find(w.id))
      res = TaskAdvances::CreateService.new(context: ctx).call(
        task_id: task.id, id: SecureRandom.uuid, progress: 20, comment: 'início', lock_version: 0
      )
      expect(res[:status]).to eq(201)
    end

    get '/api/v1/my_tasks', headers: auth_headers(novo).merge('X-Workspace-Id' => w.id)
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.size).to eq(1)
    expect(body.first['description']).to eq('Sem responsável')
  end

  # ----- §5 isolamento -----

  describe '5.1/5.2 isolamento entre workspaces (D2)' do
    # U1 dono de W1 (Person P1_w1) e MEMBRO de W9 (Person P1_w9). Uma tarefa aberta
    # em cada; a de W9 não pode aparecer em /W1/my_tasks.
    let(:u1) { owner }
    let(:w9_owner) { create(:user, name: 'Dono W9') }
    let(:w9) { make_workspace(owner: w9_owner) }

    def p1_w9
      @p1_w9 ||= Tenant.with(workspace_id: w9.id, user_id: w9_owner.id) do
        person = Person.create!(name: 'Ana em W9', user_id: u1.id)
        Membership.create!(workspace_id: w9.id, user: u1, person: person, role: 'edit')
        person
      end
    end

    def open_task_in(workspace, owner_user, person, desc:)
      Tenant.with(workspace_id: workspace.id, user_id: owner_user.id) do
        p = Project.create!(name: "P-#{desc}", position: 0)
        c = Cell.create!(project_id: p.id, name: 'C', position: 0)
        r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0)
        t = Task.create!(cat: 'A', desc: desc, position: 0, status: 'Em Andamento', progress: 10, robot_id: r.id, workspace_id: workspace.id)
        TaskAssignee.create!(task_id: t.id, person_id: person.id, workspace_id: workspace.id)
        t
      end
    end

    it '5.1 tarefa aberta de W9 não aparece em /W1/my_tasks; contagens 3 e 1' do
      3.times { |i| assign!(in_workspace(ws) { create_task(robot!, desc: "W1-#{i}", position: 0, status: 'Em Andamento', progress: 10) }, viewer) }
      open_task_in(w9, w9_owner, p1_w9, desc: 'W9-secreta')

      w1_rows = list(viewer)
      expect(w1_rows.size).to eq(3)
      expect(w1_rows.map { |r| r['description'] }).not_to include('W9-secreta')

      w9_rows = Tenant.with(workspace_id: w9.id, user_id: u1.id) do
        MyTasks::ListService.new.call(workspace_id: w9.id, person_id: p1_w9.id)[:data][:rows]
      end
      expect(w9_rows.size).to eq(1)
    end

    it '5.2 mesmo SEM o predicado ta.workspace_id, a RLS bloqueia linhas de W9' do
      open_task_in(w9, w9_owner, p1_w9, desc: 'W9-secreta')

      # consulta sem o predicado de workspace, no contexto de W1, com o person_id de W9:
      sql = <<~SQL
        SELECT t.id FROM task_assignees ta JOIN tasks t ON t.id = ta.task_id
        WHERE ta.person_id = $1 AND t.status IN ('Pendente','Em Andamento')
      SQL
      rows = in_workspace(ws) { ActiveRecord::Base.connection.exec_query(sql, 'rls', [p1_w9.id]).to_a }
      expect(rows).to be_empty # a RLS é o backstop, não o WHERE
    end
  end

  # 5.3 — exatamente 1 consulta SQL de domínio por requisição.
  it '5.3 uma requisição de 50 linhas = 1 consulta SQL de domínio (sem N+1)' do
    r = robot!
    60.times { |i| assign!(in_workspace(ws) { create_task(r, desc: "T#{i}", position: i, status: 'Em Andamento', progress: 10) }, viewer) }

    selects = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
      sql = p[:sql]
      next if p[:name] == 'SCHEMA' || sql =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET|SHOW)/i
      selects += 1 if sql =~ /\bFROM task_assignees\b/
    end
    in_workspace(ws) { MyTasks::ListService.new.call(workspace_id: ws.id, person_id: viewer.id, per_page: 50) }
    ActiveSupport::Notifications.unsubscribe(sub)

    expect(selects).to eq(1)
  end
end
