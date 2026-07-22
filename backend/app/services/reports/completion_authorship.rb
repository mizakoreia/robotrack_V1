# frozen_string_literal: true

module Reports
  # commissioning-report 6.1 (§3.8, D-R7) — quem concluiu cada tarefa e quando.
  #
  # É o AUTOR DA ENTRADA que chegou a 100, não o responsável atual (responsável muda
  # depois; a trilha não). `DISTINCT ON (task_id)` com `recorded_at DESC, created_at
  # DESC` pega a ÚLTIMA vez que a tarefa chegou a 100 — uma tarefa pode ir a 100,
  # cair a 60 e voltar; a conclusão vigente é a última. O empate exato de
  # `recorded_at` (dois avanços offline no mesmo segundo) é desempatado por
  # `created_at DESC` — determinístico, não deixamos o Postgres escolher.
  #
  # `author_name_snapshot` (não join em `people`): nome como retrato histórico
  # imutável — o documento assinado diz quem era na hora do ato.
  #
  # Os fallbacks (responsáveis atuais → traço) NÃO vivem aqui: o service os aplica,
  # porque já tem os responsáveis em memória. Isto resolve SÓ o 1º ramo.
  module CompletionAuthorship
    module_function

    # task_ids → { task_id => { author:, recorded_at: } } (só os que têm entrada de 100).
    def resolve(task_ids)
      return {} if task_ids.blank?

      conn = ActiveRecord::Base.connection
      ids = task_ids.map { |i| conn.quote(i) }.join(',')
      rows = conn.exec_query(<<~SQL, 'reports.authorship').to_a
        SELECT DISTINCT ON (task_id)
               task_id, author_name_snapshot, recorded_at
        FROM task_advances
        WHERE task_id = ANY(ARRAY[#{ids}]::uuid[]) AND to_progress = 100
        ORDER BY task_id, recorded_at DESC, created_at DESC, id DESC
      SQL

      rows.each_with_object({}) do |r, acc|
        acc[r['task_id']] = { author: r['author_name_snapshot'], recorded_at: r['recorded_at'] }
      end
    end
  end
end
