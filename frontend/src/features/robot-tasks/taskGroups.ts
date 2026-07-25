import { useCallback, useState } from 'react'
import { safeStorage } from '@/lib/safeStorage'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-grouping G1 (D-TG-1/2/4) — agrupamento por categoria e o estado de
// recolhimento. `cat` é texto livre; o servidor entrega por `position`. Agrupamos por
// PRIMEIRA APARIÇÃO (menor position, já que a lista vem ordenada): categorias não
// contíguas viram UM grupo só (corrige o título repetido do run-length antigo).

export interface TaskGroup {
  cat: string
  tasks: TaskDTO[]
}

export function groupByCategory(tasks: TaskDTO[]): TaskGroup[] {
  const order: string[] = []
  const map = new Map<string, TaskDTO[]>()
  for (const t of tasks) {
    let bucket = map.get(t.cat)
    if (!bucket) {
      bucket = []
      map.set(t.cat, bucket)
      order.push(t.cat)
    }
    bucket.push(t)
  }
  return order.map((cat) => ({ cat, tasks: map.get(cat) as TaskDTO[] }))
}

// D-TG-2 — prefixo visual A./B./C. pelo índice do grupo na tela. Acima de 26 (irreal
// aqui) cai para número, para nunca gerar um rótulo vazio.
export function groupLetter(index: number): string {
  return index < 26 ? String.fromCharCode(65 + index) : String(index + 1)
}

// D-TG-4 — estado por ROBÔ em safeStorage. Default: TUDO FECHADO; guardamos só as
// categorias ABERTAS (conjunto): ausência = fechada, então uma categoria nova nasce
// fechada e a lista abre compacta. Degrada em memória quando o storage é bloqueado.
// (chave `v2`: a v1 guardava o inverso — as recolhidas.)
export function useCategoryCollapse(robotId: string) {
  const key = `rt.taskgroups.v2.${robotId}`

  const [expanded, setExpanded] = useState<Set<string>>(() => {
    const raw = safeStorage.get('local', key)
    if (!raw) return new Set()
    try {
      const arr = JSON.parse(raw)
      return Array.isArray(arr) ? new Set(arr as string[]) : new Set()
    } catch {
      return new Set()
    }
  })

  const toggle = useCallback(
    (cat: string) => {
      setExpanded((prev) => {
        const next = new Set(prev)
        if (next.has(cat)) next.delete(cat)
        else next.add(cat)
        safeStorage.set('local', key, JSON.stringify([...next]))
        return next
      })
    },
    [key],
  )

  const isCollapsed = useCallback((cat: string) => !expanded.has(cat), [expanded])

  return { isCollapsed, toggle }
}
