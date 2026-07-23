// Fan-out de transições entre abas (offline-pwa 6.2 / D7-10). O líder anuncia
// mudanças da fila por BroadcastChannel; as abas não-líderes re-hidratam o store
// (o indicador de B e C atualiza sem recarregar). Degrada para no-op onde
// BroadcastChannel não existe — a coordenação por líder ainda funciona; só o
// espelhamento vivo entre abas some.

export const QUEUE_CHANNEL = 'robotrack-queue'
export type QueueBroadcastMessage = 'changed'

export interface QueueBroadcast {
  post: (msg?: QueueBroadcastMessage) => void
  subscribe: (cb: (msg: QueueBroadcastMessage) => void) => () => void
  close: () => void
}

type BroadcastCtor = new (name: string) => BroadcastChannel

export function createQueueBroadcast(deps: { ctor?: BroadcastCtor } = {}): QueueBroadcast {
  const Ctor = deps.ctor ?? (typeof BroadcastChannel !== 'undefined' ? BroadcastChannel : undefined)
  if (!Ctor) {
    return { post: () => {}, subscribe: () => () => {}, close: () => {} }
  }
  const ch = new Ctor(QUEUE_CHANNEL)
  return {
    post: (msg = 'changed') => ch.postMessage(msg),
    subscribe: (cb) => {
      const handler = (e: MessageEvent) => cb(e.data as QueueBroadcastMessage)
      ch.addEventListener('message', handler)
      return () => ch.removeEventListener('message', handler)
    },
    close: () => ch.close(),
  }
}
