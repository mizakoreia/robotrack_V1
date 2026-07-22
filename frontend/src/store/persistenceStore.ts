import { create } from 'zustand'

// app-shell-navigation 6.1/6.2 (D-D) — o store de persistência que ALIMENTA o
// indicador de gravação. NÃO persistido (é estado de sessão). `offline-pwa` (D7)
// será o PRODUTOR — programa contra este contrato de escrita sem redesenhar o
// indicador. `settleMutation` do mesmo id duas vezes NÃO leva `inFlight` a
// negativo (dedup por id).
export type SaveState = 'saving' | 'saved' | 'error'

interface PersistenceState {
  inFlightIds: Set<string>
  inFlight: number
  queued: number
  failed: number
  lastSavedAt: number | null
  beginMutation: (id: string) => void
  settleMutation: (id: string, ok?: boolean) => void
  setQueueDepth: (n: number) => void
  resetErrors: () => void
}

export const usePersistenceStore = create<PersistenceState>((set) => ({
  inFlightIds: new Set(),
  inFlight: 0,
  queued: 0,
  failed: 0,
  lastSavedAt: null,

  beginMutation: (id) =>
    set((s) => {
      const ids = new Set(s.inFlightIds)
      ids.add(id)
      return { inFlightIds: ids, inFlight: ids.size }
    }),

  settleMutation: (id, ok = true) =>
    set((s) => {
      const ids = new Set(s.inFlightIds)
      const had = ids.delete(id) // false se já foi liquidado: nada muda (sem negativo)
      return {
        inFlightIds: ids,
        inFlight: ids.size,
        failed: had && !ok ? s.failed + 1 : s.failed,
        lastSavedAt: had && ok ? Date.now() : s.lastSavedAt,
      }
    }),

  setQueueDepth: (n) => set({ queued: Math.max(0, n) }),
  resetErrors: () => set({ failed: 0 }),
}))

// app-shell-navigation 6.2 (D-D) — o indicador é PROJEÇÃO PURA do store, sem
// expiração por tempo: precedência `erro > salvando > salvo`. `queued = 3` com
// `inFlight = 0` é `salvando`; `erro` continua até uma escrita nova ter sucesso.
export function selectSaveState(s: Pick<PersistenceState, 'inFlight' | 'queued' | 'failed'>): SaveState {
  if (s.failed > 0) return 'error'
  if (s.inFlight > 0 || s.queued > 0) return 'saving'
  return 'saved'
}
