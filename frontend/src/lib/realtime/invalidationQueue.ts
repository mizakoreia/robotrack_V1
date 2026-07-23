import type { QueryClient } from '@tanstack/react-query'
import type { QueryKey } from './eventMap'

// realtime-collaboration 5.4 / D6.2 — a fila de invalidação com COALESCÊNCIA.
//
// O envelope é ponteiro, então uma rajada (8 avanços do mesmo robô em 900 ms)
// vira 8 pedidos de invalidação da MESMA chave. Sem coalescência, 8 refetches.
// A fila deduplica por chave (serializada) e drena a cada 250 ms → 1 refetch.
//
// `refetchType: 'active'`: query MONTADA refaz agora; query desmontada é só
// marcada stale (refaz ao remontar), sem disparar requisição para uma tela que
// ninguém está olhando.
export class InvalidationQueue {
  private pending = new Map<string, QueryKey>()
  private timer: ReturnType<typeof setTimeout> | null = null

  constructor(
    private readonly client: QueryClient,
    private readonly intervalMs = 250,
  ) {}

  enqueue(keys: QueryKey[]): void {
    for (const key of keys) this.pending.set(JSON.stringify(key), key)
    if (this.timer === null && this.pending.size > 0) {
      this.timer = setTimeout(() => this.drain(), this.intervalMs)
    }
  }

  // Drena a fila: invalida cada chave única acumulada. Público para o teste
  // forçar a drenagem sem depender do relógio.
  drain(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer)
      this.timer = null
    }
    const keys = [...this.pending.values()]
    this.pending.clear()
    for (const queryKey of keys) {
      void this.client.invalidateQueries({ queryKey, refetchType: 'active' })
    }
  }

  // Descarta a fila sem invalidar (troca de workspace / desmontagem).
  clear(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer)
      this.timer = null
    }
    this.pending.clear()
  }

  get size(): number {
    return this.pending.size
  }
}
