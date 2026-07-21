# frozen_string_literal: true

# progress-advances G1 / Migration D (§2.2, D-CHK).
#
# Só o lado INCONDICIONALMENTE verdadeiro vira constraint: `Concluído ⇒ 100`. A
# inversa (`100 ⇒ Concluído`) NÃO — reabrir uma tarefa concluída para
# `Em Andamento` mantém o progresso em 100 por §2.2, e uma bi-implicação tornaria
# a reabertura impossível. `(Em Andamento, 0)` e `(Em Andamento, 100)` são estados
# legítimos.
#
# Verificação pré-destrutiva (tarefa 1.5): aborta se houver linha divergente
# (import já rodado), nunca aplica `NOT VALID` silencioso. Greenfield: 0 linhas.
class AddDoneImpliesFullToTasks < ActiveRecord::Migration[8.0]
  def up
    divergentes = select_value(
      "SELECT count(*) FROM tasks WHERE status = 'Concluído' AND progress <> 100"
    ).to_i
    if divergentes.positive?
      raise "Abortada (D-CHK): #{divergentes} tarefa(s) 'Concluído' com progress <> 100. " \
            'Corrigir o dado antes de aplicar a constraint.'
    end

    execute(<<~SQL)
      ALTER TABLE tasks ADD CONSTRAINT tasks_done_implies_full
        CHECK (status <> 'Concluído' OR progress = 100);
    SQL
  end

  def down
    execute('ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_done_implies_full;')
  end
end
