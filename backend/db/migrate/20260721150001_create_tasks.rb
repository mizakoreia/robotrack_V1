# frozen_string_literal: true

# robot-tasks 1.2–1.4 (§1.1, D-RT-3, D-RT-5, D-RT-7, D2).
#
# A Tarefa é a unidade atômica. `status` é ENUM Postgres (não string livre): o
# legado provou que status livre gera "Concluido" sem acento e quebra o rollup.
# `progress` é `smallint` + CHECK 0–100 no BANCO, não no model — `INSERT` cru com
# `progress = 101` tem de estourar. O acoplamento progresso↔status (§2.2) NÃO é
# constraint aqui: `Em Andamento` admite qualquer progresso, e a máquina de
# estados é de `progress-advances` (D-RT-3).
#
# FK COMPOSTA `(robot_id, workspace_id) → robots(id, workspace_id)`: torna
# impossível no banco uma tarefa apontar para robô de outro workspace, e o
# `ON DELETE CASCADE` faz a tarefa morrer com o robô. Exige `uq_robots_id_workspace`
# (commissioning-hierarchy — verificado).
#
# Índice único `(robot_id, lower(btrim(desc)))`: NÃO está no tasks.md de
# robot-tasks, mas task-catalog §5.1/D-TC-6 o declara como requisito sobre ESTA
# tabela (é a garantia contra dupla-inserção concorrente da sincronização
# retroativa). Robot-tasks é a dona da tabela, então o índice mora aqui
# (EXECUCAO decisão 1). Consequência: duas tarefas com a mesma `desc` normalizada
# no mesmo robô → `23505` (409 no CRUD).
class CreateTasks < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TYPE task_status AS ENUM ('Pendente', 'Em Andamento', 'Concluído', 'N/A');

      CREATE TABLE tasks (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id uuid NOT NULL REFERENCES workspaces (id),
        robot_id     uuid NOT NULL,
        cat          text NOT NULL,
        "desc"       text NOT NULL,
        weight       numeric NOT NULL DEFAULT 1,
        progress     smallint NOT NULL DEFAULT 0,
        status       task_status NOT NULL DEFAULT 'Pendente',
        position     integer NOT NULL,
        lock_version integer NOT NULL DEFAULT 0,
        created_at   timestamptz NOT NULL DEFAULT now(),
        updated_at   timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_tasks_cat      CHECK (length(btrim(cat)) BETWEEN 1 AND 120),
        CONSTRAINT chk_tasks_desc     CHECK (length(btrim("desc")) BETWEEN 1 AND 200),
        CONSTRAINT chk_tasks_weight   CHECK (weight > 0),
        CONSTRAINT chk_tasks_progress CHECK (progress BETWEEN 0 AND 100),

        CONSTRAINT uq_tasks_id_workspace UNIQUE (id, workspace_id),
        CONSTRAINT fk_tasks_robot_same_workspace
          FOREIGN KEY (robot_id, workspace_id)
          REFERENCES robots (id, workspace_id) ON DELETE CASCADE
      );

      -- Índice liderado por workspace_id: custo de RLS (a guarda de tenancy o
      -- exige em toda tabela de domínio) e varredura por tenant.
      CREATE INDEX index_tasks_on_workspace_id ON tasks (workspace_id);

      -- Leitura da tabela do robô, ordenada por posição (§3.5).
      CREATE INDEX index_tasks_on_robot_position ON tasks (robot_id, "position");

      -- task-catalog §5.1/D-TC-6: dedup do sync retroativo e chave natural da
      -- tarefa dentro do robô (EXECUCAO decisão 1).
      CREATE UNIQUE INDEX index_tasks_on_robot_lower_desc
        ON tasks (robot_id, lower(btrim("desc")));

      ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
      ALTER TABLE tasks FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON tasks
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TABLE IF EXISTS tasks;
      DROP TYPE IF EXISTS task_status;
    SQL
  end
end
