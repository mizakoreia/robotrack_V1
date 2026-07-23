import type { QueryKey } from './eventMap'
import type { WorkspaceSyncResult } from '../api/endpoints'

// realtime-collaboration 7.4 / D6.5 — traduz a resposta do `/sync` em chaves a
// invalidar na reconexão.
//
// `gap: true` (queda longa / servidor não determinou) → subárvore inteira
// `['ws', w]` (um refetch completo é barato para o tamanho de dado do RoboTrack).
// Senão, invalida por TIPO tocado. Os tipos são grossos (sem ids): os agregados
// (`overview`) e as listas que dá para endereçar sem id cobrem o essencial — as
// tabelas id-específicas que o usuário está vendo já foram mantidas frescas pelo
// polling do modo degradado até aqui.
const KIND_KEYS: Record<string, (w: string) => QueryKey[]> = {
  project: (w) => [['ws', w, 'projects'], ['ws', w, 'overview']],
  cell: (w) => [['ws', w, 'overview']],
  robot: (w) => [['ws', w, 'overview']],
  task: (w) => [['ws', w, 'my-tasks'], ['ws', w, 'overview']],
  task_advance: (w) => [['ws', w, 'my-tasks'], ['ws', w, 'overview']],
  membership: (w) => [['ws', w, 'members'], ['ws', w, 'people']],
  notification: (w) => [['ws', w, 'notifications']],
}

export function reconcileKeys(wsId: string, result: WorkspaceSyncResult): QueryKey[] {
  if (result.gap) return [['ws', wsId]]
  if (!result.entity_kinds?.length) return []
  const keys = result.entity_kinds.flatMap((kind) => KIND_KEYS[kind]?.(wsId) ?? [['ws', wsId]])
  // dedup por serialização
  const seen = new Set<string>()
  return keys.filter((k) => {
    const s = JSON.stringify(k)
    if (seen.has(s)) return false
    seen.add(s)
    return true
  })
}
