import { useEffect } from 'react'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { useRealtimeStore } from '@/store/realtimeStore'
import { useOfflineQueueStore } from '@/store/offlineQueueStore'
import { startOfflineSync } from '@/lib/offline/sync'

// Ciclo de vida da sincronização offline (offline-pwa 6.1/6.2), montado na casca.
// Hidrata a projeção da fila para o workspace corrente e orquestra a drenagem sob
// eleição de líder + broadcast. Em teste é desligado (os módulos são exercitados
// direto, sem IndexedDB real nem timers), igual ao `useRealtime`.
function offlineSyncEnabled(): boolean {
  const env = (import.meta as { env?: Record<string, string> }).env ?? {}
  if (env.MODE === 'test') return false
  return env.VITE_REALTIME_ENABLED !== 'false'
}

export function useOfflineSync(): void {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  useEffect(() => {
    if (!offlineSyncEnabled() || !wsId) return

    // Projeção escopada por workspace: a fila de W1 não aparece em W2.
    void useOfflineQueueStore.getState().setWorkspace(wsId)

    // `originId` do realtimeStore é POR ABA — serve de tabId da eleição de líder.
    const tabId = useRealtimeStore.getState().originId
    const stop = startOfflineSync({ tabId })

    return () => {
      stop()
      void useOfflineQueueStore.getState().setWorkspace(null)
    }
  }, [wsId])
}
