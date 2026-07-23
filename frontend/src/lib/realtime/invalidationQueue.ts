import type { QueryClient } from '@tanstack/react-query'
import type { QueryKey } from './eventMap'
import type { InvalidationGate } from './invalidationGate'

// realtime-collaboration 5.4 + 6.2/6.3 / D6.2, D6.4 — a fila de invalidação com
// COALESCÊNCIA e REPRESAMENTO.
//
// Coalescência (5.4): rajada da mesma chave em 250 ms → 1 refetch; dedup por
// chave; `refetchType: 'active'` (query desmontada só marca stale).
//
// Represamento (6.2/6.3): no dreno, uma chave represada pelo gate (mutação em voo
// ou fila offline) não invalida agora — vai para `deferred` e é reavaliada quando
// uma mutação assenta (`onSettled`, sucesso ou erro). Teto de 30 s: represada além
// disso, invalida assim mesmo e marca a tela como NÃO-sincronizada (degradação
// honesta), em vez de mentir indefinidamente.
export interface InvalidationQueueOptions {
  intervalMs?: number
  gate?: InvalidationGate
  ceilingMs?: number
  onCeilingBreach?: () => void
  onFullyDrained?: () => void
  now?: () => number
}

export class InvalidationQueue {
  private readonly intervalMs: number
  private readonly gate?: InvalidationGate
  private readonly ceilingMs: number
  private readonly onCeilingBreach?: () => void
  private readonly onFullyDrained?: () => void
  private readonly now: () => number

  private pending = new Map<string, QueryKey>()
  private deferred = new Map<string, { key: QueryKey; since: number }>()
  private timer: ReturnType<typeof setTimeout> | null = null
  private ceilingTimer: ReturnType<typeof setTimeout> | null = null
  private unsubscribeGate: (() => void) | null = null

  constructor(
    private readonly client: QueryClient,
    opts: InvalidationQueueOptions | number = {},
  ) {
    // Compat: o G5 chamava `new InvalidationQueue(client, intervalMs)`.
    const o: InvalidationQueueOptions = typeof opts === 'number' ? { intervalMs: opts } : opts
    this.intervalMs = o.intervalMs ?? 250
    this.gate = o.gate
    this.ceilingMs = o.ceilingMs ?? 30_000
    this.onCeilingBreach = o.onCeilingBreach
    this.onFullyDrained = o.onFullyDrained
    this.now = o.now ?? (() => Date.now())
    if (this.gate) this.unsubscribeGate = this.gate.subscribeSettle(() => this.drainDeferred())
  }

  enqueue(keys: QueryKey[]): void {
    for (const key of keys) this.pending.set(JSON.stringify(key), key)
    if (this.timer === null && this.pending.size > 0) {
      this.timer = setTimeout(() => this.drain(), this.intervalMs)
    }
  }

  // Dreno da coalescência: invalida o que não está represado; represa o resto.
  drain(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer)
      this.timer = null
    }
    for (const [serial, key] of this.pending) {
      if (this.gate?.isDammed(key)) {
        if (!this.deferred.has(serial)) this.deferred.set(serial, { key, since: this.now() })
      } else {
        this.invalidate(key)
      }
    }
    this.pending.clear()
    this.reconcile(true)
  }

  // Uma mutação assentou: reavalia o represado (dam pode ter caído).
  drainDeferred(): void {
    for (const [serial, entry] of this.deferred) {
      if (!this.gate || !this.gate.isDammed(entry.key)) {
        this.invalidate(entry.key)
        this.deferred.delete(serial)
      }
    }
    this.reconcile(true)
  }

  // Arma/limpa o timer do teto e resolve o flag de sincronização.
  private reconcile(syncedWhenEmpty: boolean): void {
    if (this.ceilingTimer !== null) {
      clearTimeout(this.ceilingTimer)
      this.ceilingTimer = null
    }
    if (this.deferred.size === 0) {
      if (syncedWhenEmpty) this.onFullyDrained?.()
      return
    }
    const oldest = Math.min(...[...this.deferred.values()].map((d) => d.since))
    const wait = Math.max(0, this.ceilingMs - (this.now() - oldest))
    this.ceilingTimer = setTimeout(() => this.enforceCeiling(), wait)
  }

  // Teto de 30 s: força a invalidação mesmo com o dam ativo e admite a
  // dessincronização. NÃO volta a "sincronizado" ao esvaziar — só quando a
  // mutação realmente assentar (via drainDeferred).
  private enforceCeiling(): void {
    this.ceilingTimer = null
    const t = this.now()
    let breached = false
    for (const [serial, entry] of this.deferred) {
      if (t - entry.since >= this.ceilingMs) {
        this.invalidate(entry.key)
        this.deferred.delete(serial)
        breached = true
      }
    }
    if (breached) this.onCeilingBreach?.()
    this.reconcile(false)
  }

  private invalidate(queryKey: QueryKey): void {
    void this.client.invalidateQueries({ queryKey, refetchType: 'active' })
  }

  clear(): void {
    for (const timer of [this.timer, this.ceilingTimer]) if (timer !== null) clearTimeout(timer)
    this.timer = null
    this.ceilingTimer = null
    this.pending.clear()
    this.deferred.clear()
  }

  dispose(): void {
    this.clear()
    this.unsubscribeGate?.()
    this.unsubscribeGate = null
  }

  get size(): number {
    return this.pending.size
  }
  get deferredSize(): number {
    return this.deferred.size
  }
}
