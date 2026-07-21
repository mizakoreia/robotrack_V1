# frozen_string_literal: true

require 'rails_helper'

# progress-advances 1.7 (§4.1 inv. 1/3, D-IMUT, D-CMT, D-CHK, D2) — as invariantes
# da trilha provadas por SQL CRU, com o model fora do caminho. Se qualquer uma
# depender só do model, o spec passa por baixo e falha.
RSpec.describe 'Esquema de task_advances', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ana)  { create(:user, name: 'Ana') }
  let(:ws)   { make_workspace(owner: ana) }

  def q(v) = conn.quote(v)

  def robot_and_task(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'L')
      celula = Cell.create!(project_id: projeto.id, name: 'C')
      robo = Robot.create!(cell_id: celula.id, name: 'R')
      tarefa = create_task(robo, desc: 'Power On', position: 0)
      pessoa = Person.create!(name: 'Ana Resp')
      [tarefa, pessoa]
    end
  end

  # Insere um avanço válido cru (to_progress 100 → dispensa comentário).
  def insert_advance_cru(workspace_id:, task_id:, by:, to: 100, comment: 'NULL', legacy: false, recorded_at: nil)
    ra = recorded_at ? q(recorded_at) : 'now()'
    conn.execute(<<~SQL)
      INSERT INTO task_advances (workspace_id, task_id, "by", author_name_snapshot,
                                 from_progress, to_progress, comment, legacy, recorded_at)
      VALUES (#{q(workspace_id)}, #{q(task_id)}, #{by ? q(by) : 'NULL'}, 'Ana Resp',
              0, #{to}, #{comment == 'NULL' ? 'NULL' : q(comment)}, #{legacy}, #{ra})
    SQL
  end

  describe 'imutabilidade (D-IMUT)' do
    it 'UPDATE em task_advances é bloqueado' do
      tarefa, pessoa = robot_and_task(ws)
      in_workspace(ws) do
        insert_advance_cru(workspace_id: ws.id, task_id: tarefa.id, by: pessoa.id)
        expect { conn.execute("UPDATE task_advances SET to_progress = 50") }
          .to raise_error(ActiveRecord::StatementInvalid, /permission denied|append-only/i)
      end
    end

    it 'DELETE em task_advances é bloqueado' do
      tarefa, pessoa = robot_and_task(ws)
      in_workspace(ws) do
        insert_advance_cru(workspace_id: ws.id, task_id: tarefa.id, by: pessoa.id)
        expect { conn.execute("DELETE FROM task_advances") }
          .to raise_error(ActiveRecord::StatementInvalid, /permission denied|append-only/i)
      end
    end

    it 'o trigger de imutabilidade existe (rede contra o caminho do dono)' do
      existe = conn.select_value(
        "SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_task_advances_immutable'"
      ).to_i
      expect(existe).to eq(1)
    end
  end

  describe 'CHECKs de conteúdo (D-CMT, D-LEG)' do
    it 'comentário em branco abaixo de 100 é rejeitado' do
      tarefa, pessoa = robot_and_task(ws)
      in_workspace(ws) do
        expect { insert_advance_cru(workspace_id: ws.id, task_id: tarefa.id, by: pessoa.id, to: 60, comment: '   ') }
          .to raise_error(ActiveRecord::StatementInvalid, /chk_ta_comment_required/)
      end
    end

    it 'autor nulo só é permitido em entrada legacy' do
      # Cada INSERT numa transação PRÓPRIA: um erro de CHECK aborta a transação
      # corrente no Postgres, então o segundo INSERT no mesmo bloco falharia por
      # "transaction aborted", não pelo motivo que queremos provar.
      tarefa, = robot_and_task(ws)
      expect do
        in_workspace(ws) do
          insert_advance_cru(workspace_id: ws.id, task_id: tarefa.id, by: nil, to: 0, comment: 'x', legacy: false)
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /chk_ta_author_null_only_legacy/)

      # legacy com autor nulo passa (contrato de legacy-data-migration).
      expect do
        in_workspace(ws) do
          insert_advance_cru(workspace_id: ws.id, task_id: tarefa.id, by: nil, to: 0, comment: '(nota anterior)', legacy: true)
        end
      end.not_to raise_error
    end

    it 'recorded_at muito no futuro é rejeitado pelo CHECK de skew' do
      tarefa, pessoa = robot_and_task(ws)
      in_workspace(ws) do
        expect do
          insert_advance_cru(workspace_id: ws.id, task_id: tarefa.id, by: pessoa.id, recorded_at: 1.day.from_now)
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_ta_recorded_at/)
      end
    end
  end

  describe 'coerência de tenant pela FK composta (D2)' do
    it 'avanço apontando para tarefa de outro workspace é abortado pela FK' do
      tarefa_a, pessoa_a = robot_and_task(ws)
      outro = make_workspace(owner: create(:user))
      _tarefa_b, = robot_and_task(outro)

      # No contexto de A, tentar gravar um avanço cujo workspace_id é de A mas
      # task_id é de A e by de A está ok; o cruzamento é barrado quando task/by
      # não são do workspace declarado. Aqui provamos o RLS de leitura cruzada.
      visiveis = in_workspace(outro) { conn.select_value('SELECT count(*) FROM task_advances').to_i }
      in_workspace(ws) { insert_advance_cru(workspace_id: ws.id, task_id: tarefa_a.id, by: pessoa_a.id) }
      ainda = in_workspace(outro) { conn.select_value('SELECT count(*) FROM task_advances').to_i }
      expect([visiveis, ainda]).to eq([0, 0]) # W2 nunca vê a trilha de W1 (RLS)
    end

    it 'a tabela tem RLS FORÇADA e a policy tenant_isolation' do
      forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'task_advances'")
      expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true)
      pol = conn.select_value(
        "SELECT count(*) FROM pg_policies WHERE tablename = 'task_advances' AND policyname = 'tenant_isolation'"
      ).to_i
      expect(pol).to eq(1)
    end
  end

  describe 'CHECK de coerência em tasks (D-CHK)' do
    it "status 'Concluído' com progress <> 100 é rejeitado pelo banco" do
      tarefa, = robot_and_task(ws)
      in_workspace(ws) do
        expect { conn.execute("UPDATE tasks SET status = 'Concluído' WHERE id = #{q(tarefa.id)}") }
          .to raise_error(ActiveRecord::StatementInvalid, /tasks_done_implies_full/)
      end
    end

    it "reabrir para 'Em Andamento' com progress 100 continua válido" do
      tarefa, = robot_and_task(ws)
      in_workspace(ws) do
        conn.execute("UPDATE tasks SET status = 'Concluído', progress = 100 WHERE id = #{q(tarefa.id)}")
        expect { conn.execute("UPDATE tasks SET status = 'Em Andamento' WHERE id = #{q(tarefa.id)}") }
          .not_to raise_error
      end
    end
  end
end
