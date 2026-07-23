# frozen_string_literal: true

module Legacy
  # legacy-data-migration 8.1/8.2 (§2.1, D-LDM-5) — o ORÁCULO da validação. Reimplementa o
  # progresso ponderado de §2.1 em Ruby PURO a partir do JSON canônico (sem AR, sem a view,
  # sem `BulkRecompute`) e compara com o `progress_cache` do robô importado. Se reusasse o
  # código do domínio, provaria só que o código concorda consigo mesmo — uma reimplementação
  # independente prova a TRADUÇÃO. Diferença tolerada: ZERO.
  #
  # §2.1: média ponderada por peso IGNORANDO `N/A`; robô sem tarefas (importáveis) = 0; robô
  # só com `N/A` = 100. Espelha o `robot_weighted_progress` (round(Σwp/Σw) sobre não-N/A),
  # mas calculado com Rational — sem erro de float no arredondamento meio-a-meio.
  #
  # A amostra é DETERMINÍSTICA e ADVERSARIAL (nunca aleatória): ≥20 robôs, obrigatoriamente
  # incluindo sem-tarefas, só-`N/A`, pesos≠1, progresso parcial e o de maior nº de tarefas —
  # os casos que uma amostra aleatória de `Pendente@0%` nunca mediria.
  module SampleValidator
    APPLICATIONS = ImportService::APPLICATIONS
    VALID_STATUS = StatusDerivation::VALID
    MIN_SAMPLE = 20

    module_function

    # Progresso §2.1 esperado de um robô, a partir do JSON (as tarefas que IMPORTARIAM:
    # quarentenadas — progress fora de 0–100 ou status fora do enum — não entram, como no import).
    def robot_progress(robot_json)
      tasks = importable_tasks(robot_json)
      return 0 if tasks.empty?

      non_na = tasks.reject { |t| t['status'].to_s == 'N/A' }
      return 100 if non_na.empty?

      num = non_na.sum(0r) { |t| weight(t) * progress(t) }
      den = non_na.sum(0r) { |t| weight(t) }
      (num / den).round # round-half-away-from-zero, igual ao round() do Postgres
    end

    def importable_tasks(robot_json)
      array(robot_json['tasks']).select do |t|
        p = t['progress'].to_i
        p >= 0 && p <= 100 && VALID_STATUS.include?(t['status'].to_s)
      end
    end

    # --- seleção determinística e adversarial ---

    # Devolve [{ legacy_path:, robot_id:, robot: }] dos robôs amostrados (só os IMPORTÁVEIS —
    # robô com application fora do enum não entra, não tem progress_cache para comparar).
    def select_sample(canonical, min: MIN_SAMPLE)
      candidates = enumerate_robots(canonical).select { |r| APPLICATIONS.include?(r[:robot]['application']) }
      return candidates if candidates.size <= min

      sorted = candidates.sort_by { |r| r[:legacy_path] }
      picked = mandatory(sorted)
      sorted.each { |r| picked << r if picked.size < min && picked.none? { |p| p[:robot_id] == r[:robot_id] } }
      picked.sort_by { |r| r[:legacy_path] } # reprodutível
    end

    # Um representante de cada caso-limite (o 1º por caminho ordenado) + o de mais tarefas.
    def mandatory(sorted)
      picks = []
      add = ->(r) { picks << r if r && picks.none? { |p| p[:robot_id] == r[:robot_id] } }
      add.call(sorted.find { |r| importable_tasks(r[:robot]).empty? })
      add.call(sorted.find { |r| non_empty_all_na?(r[:robot]) })
      add.call(sorted.find { |r| importable_tasks(r[:robot]).any? { |t| weight(t) != 1 } })
      add.call(sorted.find { |r| importable_tasks(r[:robot]).any? { |t| partial?(t) } })
      add.call(sorted.max_by { |r| importable_tasks(r[:robot]).size })
      picks
    end

    def enumerate_robots(canonical)
      lws = canonical.dig('workspace', 'id')
      out = []
      Array(canonical['projects']).each do |p|
        ppath = IdDerivation.project_path(lws, p['id'])
        array(p['cells']).each do |c|
          cpath = "#{ppath}/cell:#{IdDerivation.ref(c, array(p['cells']).index(c))}"
          array(c['robots']).each_with_index do |r, i|
            rpath = "#{cpath}/robot:#{IdDerivation.ref(r, i)}"
            out << { legacy_path: rpath, robot_id: IdDerivation.uuid(rpath), robot: r }
          end
        end
      end
      out
    end

    # --- comparação ---

    # Compara cada robô amostrado: expected (do arquivo) vs progress_cache (do banco).
    # Pressupõe contexto de tenant aberto e `BulkRecompute` já rodado. Devolve as divergências.
    def diffs(sample)
      sample.filter_map do |r|
        robot = ::Robot.find_by(id: r[:robot_id])
        next if robot.nil?

        expected = robot_progress(r[:robot])
        actual = robot.progress_cache
        { legacy_path: r[:legacy_path], expected: expected, actual: actual } if expected != actual
      end
    end

    def weight(task)
      w = task['weight']
      w.is_a?(Numeric) && w.positive? ? w.to_r : 1r
    end

    def progress(task) = task['progress'].to_i
    def partial?(task) = task['status'].to_s != 'N/A' && progress(task).positive? && progress(task) < 100
    def non_empty_all_na?(robot) = (t = importable_tasks(robot)).any? && t.all? { |x| x['status'].to_s == 'N/A' }
    def array(value) = value.is_a?(Array) ? value : []
  end
end
