import type { TaskDTO } from '../../lib/api/endpoints'

export type TaskStatus = TaskDTO['status']

// robot-task-table 2.1 (§2.2) — o espelho client-side da tabela-verdade de
// status→progresso da `ApplyTransitionService`, usado SÓ para pré-visualizar o
// `para%` no modal quando a escolha veio do StatusSelect. A resolução que vale é
// a do servidor (o envio leva `status`, não este número): se as duas divergirem,
// a UI mostra o que o servidor devolveu, nunca este cálculo.
export function deriveStatusTarget(status: TaskStatus, progress: number): number {
  switch (status) {
    case 'Concluído':
      return 100
    case 'Pendente':
    case 'N/A':
      return 0
    case 'Em Andamento':
      return progress // §2.2 — progresso inalterado (pares (Em Andamento, 0) e (…, 100) são legítimos)
  }
}
