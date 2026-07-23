import { apiClient } from '../api/client'
import { drainQueue, type SendResult } from './drain'
import { probeHealth } from './health'
import { runAsLeader } from './leader'
import { createQueueBroadcast, type QueueBroadcast } from './broadcast'
import { installDrainTriggers } from './triggers'
import { useOfflineQueueStore } from '../../store/offlineQueueStore'
import type { QueuedMutation } from './types'

// Cola da sincronização offline (offline-pwa 6.1/6.2). Mapeia um item da fila para
// uma chamada real e orquestra a drenagem sob eleição de líder + broadcast.

// Traduz o comando da fila em uma chamada do apiClient. 2xx → sucesso; AxiosError
// vira SendResult (status + corpo) para a classificação de D7-5.
export async function sendMutation(m: QueuedMutation): Promise<SendResult> {
  try {
    switch (m.method) {
      case 'POST':
        await apiClient.post(m.url, m.body)
        break
      case 'PATCH':
        await apiClient.patch(m.url, m.body)
        break
      case 'PUT':
        await apiClient.put(m.url, m.body)
        break
      case 'DELETE':
        await apiClient.delete(m.url)
        break
    }
    return { ok: true, status: 200 }
  } catch (e) {
    const err = e as { response?: { status?: number; data?: unknown } }
    const status = err.response?.status ?? 0
    return { ok: false, status, networkError: !err.response, body: err.response?.data }
  }
}

export interface OfflineSyncDeps {
  tabId: string
  send?: (m: QueuedMutation) => Promise<SendResult>
  probe?: () => Promise<boolean>
  broadcast?: QueueBroadcast
  installTriggers?: typeof installDrainTriggers
}

// Instala a orquestração: um runner que drena SÓ se esta aba for a líder, avisa as
// outras abas por broadcast a cada mudança, e é chamado pelos gatilhos (todos
// atrás da sonda de saúde). Devolve o teardown.
export function startOfflineSync(deps: OfflineSyncDeps): () => void {
  const broadcast = deps.broadcast ?? createQueueBroadcast()
  const send = deps.send ?? sendMutation
  const probe = deps.probe ?? (() => probeHealth())
  const install = deps.installTriggers ?? installDrainTriggers

  const unsubscribe = broadcast.subscribe(() => {
    void useOfflineQueueStore.getState().refresh()
  })

  const runner = async () => {
    await runAsLeader(
      () =>
        drainQueue({
          probe,
          send,
          onChange: () => {
            void useOfflineQueueStore.getState().refresh()
            broadcast.post()
          },
        }),
      { tabId: deps.tabId },
    )
  }

  const stopTriggers = install({ run: runner })

  return () => {
    unsubscribe()
    stopTriggers()
    broadcast.close()
  }
}
