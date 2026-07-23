import { probeStorageLevel } from '../safeStorage'
import { useOfflineQueueStore } from '../../store/offlineQueueStore'
import { isPending } from './overlay'
import type { OfflinePendingProbe } from '../realtime/invalidationGate'

// Ponte D6×D7 (offline-pwa 7.3 / D7-11). Em `memory-only` a fila é DESLIGADA
// (D7-11): prometer durabilidade sem lastro é a desonestidade de estado que o
// PRODUCT.md proíbe — a mutation vai direto à rede e falha visivelmente offline.
export function queueEnabled(): boolean {
  return probeStorageLevel() !== 'memory-only'
}

// `hasPendingFor` liga a fila real ao gate de represamento de D6: o gate segura a
// invalidação por item EM VOO (React Query) E por item na fila offline (isto), de
// modo que um evento ao vivo não sobrescreva a sobreposição otimista.
export const queueOfflineProbe: OfflinePendingProbe = {
  hasPendingFor(_kind, id) {
    if (!queueEnabled()) return false
    return useOfflineQueueStore
      .getState()
      .mutations.some((m) => isPending(m) && (m.resource_uuid === id || m.depends_on.includes(id)))
  },
}
