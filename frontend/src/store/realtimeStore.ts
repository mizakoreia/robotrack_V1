import { create } from 'zustand'

// realtime-collaboration 5.2 (§Req. fallback, D6.5/D6.6) — estado de CLIENTE do
// tempo real (não de servidor, então zustand, não React Query). A máquina de
// transporte é lida pelo indicador de conexão da topbar (7.3): sem ela, o modo
// degradado é invisível e um `/cable` mal roteado passa meses despercebido.
//
// - `transport`: connecting → live | connecting → degraded (polling) → connecting
//   (retry) | offline. As TRANSIÇÕES de degradação/backoff são do G7; aqui fica o
//   estado e os setters.
// - `lastSeq[wsId]`: o maior `seq` já visto por workspace — é o que a
//   reconciliação (`/sync?since=`) manda ao reconectar (G7 §7.4).
// - `originId`: UUID da ABA (memória, estável na sessão). Vai no header
//   `X-RoboTrack-Origin` (G6) e é como o cliente descarta o próprio eco.
export type TransportState = 'connecting' | 'live' | 'degraded' | 'offline'

interface RealtimeState {
  transport: TransportState
  lastSeq: Record<string, number>
  originId: string
  setTransport: (s: TransportState) => void
  noteSeq: (wsId: string, seq: number) => void
  reset: () => void
}

function makeOriginId(): string {
  try {
    return crypto.randomUUID()
  } catch {
    return `o-${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`
  }
}

export const useRealtimeStore = create<RealtimeState>((set, get) => ({
  transport: 'connecting',
  lastSeq: {},
  originId: makeOriginId(),

  setTransport: (transport) => set({ transport }),

  // Só AVANÇA — um envelope fora de ordem (reconexão parcial do ActionCable) não
  // pode fazer o `since` retroceder e re-pedir o que já veio.
  noteSeq: (wsId, seq) => {
    const cur = get().lastSeq[wsId] ?? 0
    if (seq > cur) set({ lastSeq: { ...get().lastSeq, [wsId]: seq } })
  },

  // Troca de workspace / logout: zera transporte e seqs (o `originId` da aba
  // sobrevive — é identidade da aba, não do workspace).
  reset: () => set({ transport: 'connecting', lastSeq: {} }),
}))
