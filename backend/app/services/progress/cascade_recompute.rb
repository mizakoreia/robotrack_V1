# frozen_string_literal: true

module Progress
  # progress-rollup 2.1 (§D5.b) — o ponto de escrita ÚNICO do `progress_cache` no
  # caminho quente. Executa, na MESMA transação da mutação que o invalida, a
  # cascata em ordem FIXA robô → célula → projeto.
  #
  # A ordem fixa é o que evita deadlock entre dois avanços concorrentes na mesma
  # subárvore: duas transações que tocam o mesmo robô serializam no lock da linha
  # do robô, depois da célula, depois do projeto — sempre na mesma ordem, nunca em
  # ordens opostas.
  #
  # Os valores vêm das VIEWS (que computam ao vivo das tarefas), não de outros
  # caches — então a ordem não afeta a correção, só a serialização dos locks.
  # `progress_cached_at = now()` registra quando o cache foi calculado.
  module CascadeRecompute
    module_function

    # Caminho quente: um robô mudou (avanço, tarefa criada/excluída). Recalcula o
    # robô, sua célula e seu projeto.
    def call(robot_id:)
      return if Progress.cascade_suppressed?

      exec(<<~SQL, robot_id)
        UPDATE robots r
        SET progress_cache = rwp.value, progress_cached_at = now()
        FROM robot_weighted_progress rwp
        WHERE rwp.robot_id = r.id AND r.id = %s;
      SQL
      recompute_cell_of_robot(robot_id)
      recompute_project_of_robot(robot_id)
    end

    # Um robô saiu de uma célula (excluído/movido) e pode nem existir mais:
    # recalcula a célula e o projeto dela a partir do `cell_id`.
    def for_cell(cell_id:)
      return if Progress.cascade_suppressed?

      exec(<<~SQL, cell_id)
        UPDATE cells c
        SET progress_cache = cwp.value, progress_cached_at = now()
        FROM cell_weighted_progress cwp
        WHERE cwp.cell_id = c.id AND c.id = %s;
      SQL
      exec(<<~SQL, cell_id)
        UPDATE projects p
        SET progress_cache = pwp.value, progress_cached_at = now()
        FROM project_weighted_progress pwp
        WHERE pwp.project_id = p.id
          AND p.id = (SELECT project_id FROM cells WHERE id = %s);
      SQL
    end

    def for_project(project_id:)
      return if Progress.cascade_suppressed?

      exec(<<~SQL, project_id)
        UPDATE projects p
        SET progress_cache = pwp.value, progress_cached_at = now()
        FROM project_weighted_progress pwp
        WHERE pwp.project_id = p.id AND p.id = %s;
      SQL
    end

    def recompute_cell_of_robot(robot_id)
      exec(<<~SQL, robot_id)
        UPDATE cells c
        SET progress_cache = cwp.value, progress_cached_at = now()
        FROM cell_weighted_progress cwp
        WHERE cwp.cell_id = c.id
          AND c.id = (SELECT cell_id FROM robots WHERE id = %s);
      SQL
    end

    def recompute_project_of_robot(robot_id)
      exec(<<~SQL, robot_id)
        UPDATE projects p
        SET progress_cache = pwp.value, progress_cached_at = now()
        FROM project_weighted_progress pwp
        WHERE pwp.project_id = p.id
          AND p.id = (SELECT c.project_id FROM cells c
                      JOIN robots r ON r.cell_id = c.id WHERE r.id = %s);
      SQL
    end

    def exec(sql, id)
      quoted = ActiveRecord::Base.connection.quote(id)
      ActiveRecord::Base.connection.execute(format(sql, quoted))
    end
  end
end
