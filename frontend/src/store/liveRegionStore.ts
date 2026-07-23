import { create } from 'zustand'

// quality-and-accessibility 5.1 (D-QA-4) — as regiões vivas do shell. O ponto: uma
// região `aria-live` inserida no DOM JUNTO com seu texto NÃO é anunciada por leitor
// nenhum (o leitor precisa observar a região vazia e vê-la MUDAR). Por isso as três
// regiões vivem montadas e VAZIAS no shell (LiveRegions), e as mensagens são
// empurradas para cá — nunca renderizadas junto com o nó da região.
//   status        → polite, atomic (conexão/persistência: "Sem conexão")
//   notifications → polite (contador do centro de notificações)
//   alerts        → assertive, role=alert (perda de acesso ao vivo — interrompe)
export type LiveKind = 'status' | 'notifications' | 'alerts'

type LiveRegionState = {
  status: string
  notifications: string
  alerts: string
  announce: (kind: LiveKind, message: string) => void
}

export const useLiveRegionStore = create<LiveRegionState>((set) => ({
  status: '',
  notifications: '',
  alerts: '',
  announce: (kind, message) => set({ [kind]: message } as Pick<LiveRegionState, LiveKind>),
}))

// Atalho fora de componente (services/effects): `announce('alerts', '…')`.
export function announce(kind: LiveKind, message: string): void {
  useLiveRegionStore.getState().announce(kind, message)
}
