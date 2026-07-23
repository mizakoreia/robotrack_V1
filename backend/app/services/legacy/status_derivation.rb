# frozen_string_literal: true

module Legacy
  # legacy-data-migration 6.3 (§2.2, D-LDM-7) — a máquina de estados de §2.2 e a regra de
  # incoerência status↔progresso. O único acoplamento que o banco IMPÕE é
  # `tasks_done_implies_full` (`Concluído` ⇒ `progress = 100`); os demais pares são livres.
  # Por isso a ÚNICA incoerência a tratar é `Concluído` com `progress ≠ 100`: aí `progress`
  # é a fonte de verdade e o `status` é DERIVADO dele (design D-LDM-7), com a divergência no
  # relatório. `N/A` é preservado (é rótulo de exclusão, não função do progresso).
  module StatusDerivation
    VALID = %w[Pendente Em\ Andamento Concluído N/A].freeze

    module_function

    def valid?(status) = VALID.include?(status)

    # status derivado do progresso (§2.2): 100→Concluído, (0,100)→Em Andamento, 0→Pendente.
    def from_progress(progress)
      return 'Concluído' if progress == 100
      return 'Em Andamento' if progress.positive?

      'Pendente'
    end

    # Devolve [status_final, derivado?]. Coerente (ou N/A) → mantém; `Concluído` com
    # progress≠100 → deriva de progress e sinaliza (o chamador reporta status_derivado_de_progresso).
    def reconcile(status, progress)
      return [status, false] if status == 'N/A'
      return [from_progress(progress), true] if status == 'Concluído' && progress != 100

      [status, false]
    end
  end
end
