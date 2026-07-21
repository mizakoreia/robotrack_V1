# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 1.6 (§1.1, §4.1 inv. 1) — os cenários negativos do esquema de
# `tasks` provados por SQL CRU, com o model fora do caminho. Se algum CHECK/enum/
# RLS existir só no model, o spec passa por baixo dele e falha.
RSpec.describe 'Esquema de tasks', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ana)  { create(:user) }
  let(:ws)   { make_workspace(owner: ana) }

  def q(v) = conn.quote(v)

  # Cria um robô (com projeto e célula) no contexto do workspace.
  def robot_in(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      Robot.create!(cell_id: celula.id, name: 'R-01')
    end
  end

  def insert_task_cru(workspace_id:, robot_id:, desc: 'Tarefa', progress: 0, status: 'Pendente', position: 0)
    conn.execute(<<~SQL)
      INSERT INTO tasks (workspace_id, robot_id, cat, "desc", progress, status, "position")
      VALUES (#{q(workspace_id)}, #{q(robot_id)}, 'A. Hardware', #{q(desc)},
              #{progress}, #{q(status)}::task_status, #{position})
    SQL
  end

  it 'progress = 101 falha no banco (CHECK), não na validação do model' do
    robo = robot_in(ws)
    in_workspace(ws) do
      expect { insert_task_cru(workspace_id: ws.id, robot_id: robo.id, progress: 101) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_tasks_progress/)
    end
  end

  it 'status fora do enum falha com erro de tipo (Concluido sem acento)' do
    robo = robot_in(ws)
    in_workspace(ws) do
      expect { insert_task_cru(workspace_id: ws.id, robot_id: robo.id, status: 'Concluido') }
        .to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum task_status/)
    end
  end

  it 'workspace_id nulo falha (RLS barra antes, ou o NOT NULL)' do
    robo = robot_in(ws)
    in_workspace(ws) do
      expect do
        conn.execute(<<~SQL)
          INSERT INTO tasks (robot_id, cat, "desc", "position")
          VALUES (#{q(robo.id)}, 'A. Hardware', 'Sem ws', 0)
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security|null value/)
    end
  end

  it 'RLS: SELECT sem WHERE não enxerga tarefa de outro workspace' do
    outro = make_workspace(owner: create(:user))
    robo_b = robot_in(outro)
    in_workspace(outro) { insert_task_cru(workspace_id: outro.id, robot_id: robo_b.id, desc: 'Do vizinho') }

    visiveis = in_workspace(ws) { conn.select_value('SELECT count(*) FROM tasks').to_i }
    expect(visiveis).to eq(0)
  end

  it 'FK composta: tarefa com workspace_id do contexto mas robô de OUTRO workspace é rejeitada' do
    outro = make_workspace(owner: create(:user))
    robo_b = robot_in(outro)
    in_workspace(ws) do
      expect { insert_task_cru(workspace_id: ws.id, robot_id: robo_b.id, desc: 'Injetada') }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_tasks_robot_same_workspace|violates foreign key/)
    end
  end

  it 'duas tarefas com a mesma desc normalizada no MESMO robô falham (índice único, decisão 1)' do
    robo = robot_in(ws)
    in_workspace(ws) do
      insert_task_cru(workspace_id: ws.id, robot_id: robo.id, desc: 'TCP Check')
      expect { insert_task_cru(workspace_id: ws.id, robot_id: robo.id, desc: '  tcp check  ', position: 1) }
        .to raise_error(ActiveRecord::RecordNotUnique, /robot_lower_desc/)
    end
  end

  it 'a tabela tem RLS FORÇADA e a policy tenant_isolation' do
    forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'tasks'")
    expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true)

    policies = conn.select_value(
      "SELECT count(*) FROM pg_policies WHERE tablename = 'tasks' AND policyname = 'tenant_isolation'"
    ).to_i
    expect(policies).to eq(1)
  end

  it 'o helper create_task produz tarefa válida resolvendo workspace_id do robô (sem informá-lo)' do
    robo = robot_in(ws)
    tarefa = in_workspace(ws) { create_task(robo, desc: 'Da helper') }

    expect(tarefa).to be_persisted
    expect(tarefa.workspace_id).to eq(ws.id)
    expect([tarefa.progress, tarefa.status, tarefa.weight.to_i]).to eq([0, 'Pendente', 1])
  end
end
