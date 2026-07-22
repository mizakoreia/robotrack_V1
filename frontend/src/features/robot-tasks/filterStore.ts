import { create } from 'zustand'
import type { TaskDTO } from '../../lib/api/endpoints'

// robot-task-table 1.5 (§3.5, D-RTT-1/2) — o filtro segmentado é estado de UI EFÊMERO,
// NÃO persistido (nunca URL, nunca `persist` — voltar ao robô mostra "Todos"). Derivado
// de STATUS (D-RTT-2): Pendentes = Pendente + Em Andamento; Concluídos = Concluído; `N/A`
// só em Todos. O reset na navegação é do componente (`useEffect([robotId])` + `key`).
export type TaskFilter = 'all' | 'pending' | 'done'

interface FilterState {
  filter: TaskFilter
  setFilter: (f: TaskFilter) => void
  reset: () => void
}

export const useRobotTaskFilter = create<FilterState>((set) => ({
  filter: 'all',
  setFilter: (filter) => set({ filter }),
  reset: () => set({ filter: 'all' }),
}))

export function applyFilter(tasks: TaskDTO[], filter: TaskFilter): TaskDTO[] {
  if (filter === 'pending') return tasks.filter((t) => t.status === 'Pendente' || t.status === 'Em Andamento')
  if (filter === 'done') return tasks.filter((t) => t.status === 'Concluído')
  return tasks // 'all' — inclui N/A
}
