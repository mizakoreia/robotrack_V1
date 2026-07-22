# frozen_string_literal: true

module MyTasks
  # my-tasks-view 2.4/2.5 (§3.6, D-MTV-4/6) — a consulta ÚNICA de "Minhas Tarefas".
  #
  # Driver em `task_assignees` (parte da PESSOA: dezenas a centenas de linhas), não
  # em `tasks` (dezenas de milhares) — inverter a seletividade varreria as ~28.800
  # tarefas do workspace para descartar 99%. Os joins seguem por PK até o projeto e
  # o payload é ACHATADO (cada linha traz nomes+ids de robô/célula/projeto, zero
  # requisições extras). "Aberta" = `status IN ('Pendente','Em Andamento')` — os
  # literais do ENUM REAL, a exclusão de §3.6 traduzida em inclusão (§2.2 tem 4
  # status). `workspace_id` aparece no WHERE ALÉM da RLS porque é o prefixo do
  # índice.
  #
  # Ordenação TOTAL e determinística (D-MTV-6): projeto→célula→robô→tarefa, cada
  # nível por `position` e DESEMPATADO por `id` — sem o desempate, duas linhas de
  # mesma `position` trocam de página entre requisições. Paginação por offset
  # (conjunto pequeno, ordem estável).
  #
  # A resolução do viewer (`person_id` a partir do `user_id`) e o 409 de identidade
  # ausente vivem no endpoint (3.1) — aqui o `person_id` já chega resolvido.
  class ListService
    include ApiResponseHandler

    OPEN_STATUSES = ['Pendente', 'Em Andamento'].freeze
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200

    def call(workspace_id:, person_id:, page: 1, per_page: DEFAULT_PER_PAGE)
      per = normalize_per_page(per_page)
      pg  = [page.to_i, 1].max
      offset = (pg - 1) * per

      rows = ActiveRecord::Base.connection.exec_query(
        list_sql, 'my_tasks.list', [workspace_id, person_id, per, offset]
      ).to_a

      total = ActiveRecord::Base.connection.exec_query(
        count_sql, 'my_tasks.count', [workspace_id, person_id]
      ).first['total'].to_i

      success_response({ rows: rows, page: pg, per_page: per, total: total })
    end

    private

    def normalize_per_page(value)
      n = value.to_i
      return DEFAULT_PER_PAGE if n <= 0

      [n, MAX_PER_PAGE].min
    end

    def list_sql
      <<~SQL
        SELECT t.id,
               t."desc"  AS description,
               t.status  AS status,
               t.progress AS progress,
               t.cat     AS category,
               r.id AS robot_id,   r.name AS robot_name,
               c.id AS cell_id,    c.name AS cell_name,
               p.id AS project_id, p.name AS project_name
        FROM task_assignees ta
        JOIN tasks    t ON t.id = ta.task_id
        JOIN robots   r ON r.id = t.robot_id
        JOIN cells    c ON c.id = r.cell_id
        JOIN projects p ON p.id = c.project_id
        WHERE ta.workspace_id = $1
          AND ta.person_id    = $2
          AND t.status IN ('Pendente', 'Em Andamento')
        ORDER BY p.position, p.id, c.position, c.id, r.position, r.id, t.position, t.id
        LIMIT $3 OFFSET $4
      SQL
    end

    def count_sql
      <<~SQL
        SELECT COUNT(*) AS total
        FROM task_assignees ta
        JOIN tasks t ON t.id = ta.task_id
        WHERE ta.workspace_id = $1
          AND ta.person_id    = $2
          AND t.status IN ('Pendente', 'Em Andamento')
      SQL
    end
  end
end
