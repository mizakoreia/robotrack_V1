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
      ActiveRecord::Base.transaction do
        # Força hash-join nos 3 roll-ups. Com estatística FRIA — o recompute roda
        # logo após um `insert_all` em massa (criação de robôs em lote, importação
        # legada, reset), antes de o autovacuum analisar — o otimizador estima
        # rows≈1 e escolhe NESTED-LOOP em cascata sobre as views de 3 níveis: para
        # CADA robô re-varre TODAS as tasks do workspace (index só de workspace_id),
        # ~3k×93k comparações → 15+ min. Para uma agregação do workspace INTEIRO o
        # plano correto é SEMPRE hash; o nestloop aqui é só sintoma de má estimativa,
        # não um caminho válido. `SET LOCAL` vale só nesta transação e não é `UPDATE`
        # (query_budget_spec continua vendo exatamente 3). Medido: 15+ min → ~0,1 s.
        ActiveRecord::Base.connection.execute('SET LOCAL enable_nestloop = off')

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
    end

    def exec(sql, id)
      quoted = ActiveRecord::Base.connection.quote(id)
      ActiveRecord::Base.connection.execute(format(sql, quoted))
    end
  end
end
