# frozen_string_literal: true

# progress-rollup 2.5 (D5.c) — o namespace do cálculo de progresso e a flag de
# supressão da cascata por linha.
#
# Caminhos de alto volume (importação legada, criação de robôs em lote,
# reconciliação, reset) NÃO podem disparar `CascadeRecompute` por linha — 50
# robôs × 31 tarefas seriam até 1.550 recálculos em cascata numa transação. Eles
# abrem `Progress.without_cascade { ... }` e, obrigatoriamente, chamam
# `BulkRecompute` antes do commit (o sweep de 2.6 verifica que todo bloco termina
# em BulkRecompute).
module Progress
  THREAD_KEY = :progress_cascade_suppressed

  # Suprime a cascata por linha no bloco. Reentrante (empilha e restaura).
  def self.without_cascade
    previous = Thread.current[THREAD_KEY]
    Thread.current[THREAD_KEY] = true
    yield
  ensure
    Thread.current[THREAD_KEY] = previous
  end

  def self.cascade_suppressed?
    Thread.current[THREAD_KEY] == true
  end
end
