# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 2.1–2.4 (§1.1, §3.6, D-RT-1, D-RT-2, D10/D11) — as invariantes de
# `task_assignees` provadas no banco, e a prova de que o esquema NÃO tem `resp`.
RSpec.describe 'Esquema de task_assignees', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ana)  { create(:user) }
  let(:ws)   { make_workspace(owner: ana) }

  def robot_in(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      Robot.create!(cell_id: celula.id, name: 'R-01')
    end
  end

  def person_in(workspace, name)
    in_workspace(workspace) { Person.create!(name: name) }
  end

  describe 'coerência de tenant pela FK composta (D-RT-1)' do
    it 'atribuir pessoa de WS-B a tarefa de WS-A é abortado pela FK' do
      robo_a = robot_in(ws)
      tarefa_a = in_workspace(ws) { create_task(robo_a) }

      outro = make_workspace(owner: create(:user))
      pessoa_b = person_in(outro, 'Pessoa de B')

      # No contexto de A, a pessoa de B é invisível pela RLS e a FK
      # (person_id, workspace_id=A) não casa people(id=pessoa_b, workspace_id=A).
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO task_assignees (workspace_id, task_id, person_id)
            VALUES (#{conn.quote(ws.id)}, #{conn.quote(tarefa_a.id)}, #{conn.quote(pessoa_b.id)})
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /fk_task_assignees_person_same_workspace|violates foreign key/)
      end
    end
  end

  describe 'unicidade (task_id, person_id) — §3.6' do
    it 'atribuir a mesma pessoa duas vezes à mesma tarefa falha (23505)' do
      robo = robot_in(ws)
      in_workspace(ws) do
        tarefa = create_task(robo)
        pessoa = Person.create!(name: 'Ana Resp')
        TaskAssignee.create!(task: tarefa, person: pessoa)
        expect { TaskAssignee.create!(task_id: tarefa.id, person_id: pessoa.id, workspace_id: ws.id) }
          .to raise_error(ActiveRecord::RecordNotUnique, /task_person/)
      end
    end
  end

  describe 'CASCADE de tasks, RESTRICT de people' do
    it 'excluir a tarefa remove suas atribuições (CASCADE)' do
      robo = robot_in(ws)
      in_workspace(ws) do
        tarefa = create_task(robo)
        pessoa = Person.create!(name: 'Bia Resp')
        TaskAssignee.create!(task: tarefa, person: pessoa)
        expect(TaskAssignee.where(task_id: tarefa.id).count).to eq(1)

        tarefa.destroy!
        expect(TaskAssignee.where(task_id: tarefa.id).count).to eq(0)
      end
    end

    it 'excluir uma pessoa COM atribuição é barrado (RESTRICT)' do
      robo = robot_in(ws)
      in_workspace(ws) do
        tarefa = create_task(robo)
        pessoa = Person.create!(name: 'Caio Resp')
        TaskAssignee.create!(task: tarefa, person: pessoa)

        expect { pessoa.destroy! }
          .to raise_error(ActiveRecord::InvalidForeignKey, /fk_task_assignees_person_same_workspace|violates foreign key/)
      end
    end
  end

  describe 'associação e ausência de sentinela (D10/D11)' do
    it 'tarefa sem responsável responde assignees == [], não uma Person "Não Atribuído"' do
      robo = robot_in(ws)
      in_workspace(ws) do
        tarefa = create_task(robo)
        expect(tarefa.assignees).to eq([])
      end
    end

    it 'Task#assignees devolve as Person atribuídas' do
      robo = robot_in(ws)
      in_workspace(ws) do
        tarefa = create_task(robo)
        p1 = Person.create!(name: 'Dora')
        p2 = Person.create!(name: 'Elis')
        TaskAssignee.create!(task: tarefa, person: p1)
        TaskAssignee.create!(task: tarefa, person: p2)

        expect(tarefa.reload.assignees.map(&:name)).to contain_exactly('Dora', 'Elis')
      end
    end
  end

  describe 'RLS forçada' do
    it 'task_assignees tem FORCE RLS e policy tenant_isolation' do
      forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'task_assignees'")
      expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true)
      policies = conn.select_value(
        "SELECT count(*) FROM pg_policies WHERE tablename = 'task_assignees' AND policyname = 'tenant_isolation'"
      ).to_i
      expect(policies).to eq(1)
    end
  end

  # robot-tasks 2.4 (D-RT-2) — o esquema NÃO carrega compatibilidade legada.
  describe 'ausência de `resp` (D-RT-2)' do
    it 'Task não tem coluna resp nem uma coluna de texto assignees' do
      expect(Task.column_names).not_to include('resp')
      expect(Task.column_names).not_to include('assignees')
    end

    it 'nenhum lugar do esquema tem coluna resp' do
      colunas = conn.select_values(<<~SQL)
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND column_name = 'resp'
      SQL
      expect(colunas).to be_empty
    end
  end
end
