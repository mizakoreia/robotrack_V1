import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { useRealtimeStore } from '@/store/realtimeStore'
import { initRealtime } from '@/lib/realtime/connection'
import { DegradedPoller } from '@/lib/realtime/poller'
import { reportTransportMetric } from '@/lib/realtime/metrics'

// realtime-collaboration 7.x + 9.1 — o ciclo de vida do tempo real, montado na
// casca. Conecta ao workspace corrente, (re)conecta na troca, roda o poller do
// modo degradado e emite a métrica de transporte.
//
// `VITE_REALTIME_ENABLED` (default LIGADO, 9.1): desligado, nenhuma conexão de
// Cable abre e a aplicação segue correta — rollback vira toggle. Em teste,
// desligado por padrão (os módulos são exercitados direto, sem rede).
function realtimeEnabled(): boolean {
  const env = (import.meta as { env?: Record<string, string> }).env ?? {}
  if (env.MODE === 'test') return false
  return env.VITE_REALTIME_ENABLED !== 'false'
}

export function useRealtime(): void {
  const queryClient = useQueryClient()
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  useEffect(() => {
    if (!realtimeEnabled() || !wsId) return

    const client = initRealtime(queryClient)
    const poller = new DegradedPoller({
      client: queryClient,
      getTransport: () => useRealtimeStore.getState().transport,
      subscribe: (cb) => useRealtimeStore.subscribe(cb),
    })
    const unsubMetric = useRealtimeStore.subscribe((s, prev) => {
      if (s.transport !== prev.transport) reportTransportMetric(s.transport)
    })

    poller.start()
    void client.connect(wsId)

    return () => {
      unsubMetric()
      poller.stop()
      client.disconnect()
    }
  }, [wsId, queryClient])
}
