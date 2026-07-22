# frozen_string_literal: true

module Progress
  # progress-rollup 2.5 (§D5.c) — o caminho em MASSA: recalcula os três níveis de
  # um workspace inteiro em exatamente 3 `UPDATE ... FROM` set-based, na ordem
  # robô → célula → projeto.
  #
  # Usado por: importação legada, criação de robôs em lote, reconciliação e reset.
  # Roda dentro de `Progress.without_cascade` — a cascata por linha é suprimida e
  # este recálculo em massa a substitui, uma vez, antes do commit.
  #
  # As views computam ao vivo das tarefas (não de outros caches), então os 3
  # statements são independentes na ordem de leitura — a ordem robô→célula→projeto
  # existe pela consistência de aquisição de lock, não por dependência de dado.
  module BulkRecompute
    module_function

    def call(workspace_id:)
      exec(<<~SQL, workspace_id)
        UPDATE robots r
        SET progress_cache = rwp.value, progress_cached_at = now()
        FROM robot_weighted_progress rwp
        WHERE rwp.robot_id = r.id AND r.workspace_id = %s;
      SQL
      exec(<<~SQL, workspace_id)
        UPDATE cells c
        SET progress_cache = cwp.value, progress_cached_at = now()
        FROM cell_weighted_progress cwp
        WHERE cwp.cell_id = c.id AND c.workspace_id = %s;
      SQL
      exec(<<~SQL, workspace_id)
        UPDATE projects p
        SET progress_cache = pwp.value, progress_cached_at = now()
        FROM project_weighted_progress pwp
        WHERE pwp.project_id = p.id AND p.workspace_id = %s;
      SQL
    end

    def exec(sql, id)
      quoted = ActiveRecord::Base.connection.quote(id)
      ActiveRecord::Base.connection.execute(format(sql, quoted))
    end
  end
end
