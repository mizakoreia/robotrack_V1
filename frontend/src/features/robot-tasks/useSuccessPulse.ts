import { useEffect, useRef, useState } from 'react'

// robot-task-table 6.3 (§3.5, DESIGN.md §Motion) — o pulso de confirmação aos 100%.
//
// Dispara UMA vez na transição `<100 → 100` OBSERVADA pelo cliente (D15 — o valor
// consolidado da linha, qualquer que seja o caminho: slider, ±, ou status
// Concluído). Não dispara em 100→100 (recarregar uma tarefa já concluída não
// pulsa), nem em 40→90. O `prefers-reduced-motion` é respeitado pelo próprio CSS
// (o bloco global zera `animation-duration`), então aqui só controlamos QUANDO a
// classe entra; a linha ainda atualiza para "Concluído" mesmo sem animar.
export function useSuccessPulse(progress: number): { pulsing: boolean; clear: () => void } {
  const prev = useRef(progress)
  const [pulsing, setPulsing] = useState(false)

  useEffect(() => {
    if (prev.current < 100 && progress === 100) setPulsing(true)
    prev.current = progress
  }, [progress])

  return { pulsing, clear: () => setPulsing(false) }
}
