import { create } from 'zustand'
import { listMutations } from '../lib/offline/queue'
import type { QueuedMutation, MutationState } from '../lib/offline/types'

// Projeção reativa da fila offline (offline-pwa 3.3 / D9). O IndexedDB é a fonte
// de verdade; este store é uma VISÃO em memória, escopada pelo workspace corrente
// — a fila de W1 nunca aparece nem é enviada na UI de W2. IndexedDB não emite
// eventos de mudança, então quem escreve na fila chama `refresh()` (e no G6 o
// BroadcastChannel hidrata as abas não-líderes).

const PENDING: MutationState[] = ['enqueued', 'inflight', 'blocked']

interface OfflineQueueState {
  workspaceId: string | null
  mutations: QueuedMutation[]
  setWorkspace: (id: string | null) => Promise<void>
  refresh: () => Promise<void>
}

export const useOfflineQueueStore = create<OfflineQueueState>((set, get) => ({
  workspaceId: null,
  mutations: [],

  setWorkspace: async (id) => {
    set({ workspaceId: id, mutations: [] })
    await get().refresh()
  },

  refresh: async () => {
    const wsId = get().workspaceId
    if (!wsId) {
      set({ mutations: [] })
      return
    }
    const mutations = await listMutations(wsId)
    // A troca de workspace pode ter corrido durante o await: só aplica se ainda
    // é o workspace pedido.
    if (get().workspaceId === wsId) set({ mutations })
  },
}))

// Seletores derivados (sem recomputar em cada componente).
export const selectPendingCount = (s: OfflineQueueState): number =>
  s.mutations.filter((m) => PENDING.includes(m.state)).length

export const selectHasBlocked = (s: OfflineQueueState): boolean => s.mutations.some((m) => m.state === 'blocked')

export const selectFailed = (s: OfflineQueueState): QueuedMutation[] => s.mutations.filter((m) => m.state === 'failed')
