import type { QueryClient } from '@tanstack/react-query'
import type { TransportState } from '../../store/realtimeStore'

// realtime-collaboration 7.2 / D6.6 — o FALLBACK de polling. Em `degraded` (WS
// bloqueado pelo proxy), as queries ATIVAS voltam a ser refetchadas em intervalo,
// para que o avanço de outro membro apareça mesmo sem tempo real.
//
// - 20s no ritmo de trabalho ("registrar avanço, andar até o próximo robô").
// - 60s após 5 min sem interação (documento oculto OU sem input) — e NADA quando
//   a aba está oculta (`refetchIntervalInBackground: false`): aba escondida não
//   emite requisição.
// - `offline` (sem rede) NÃO pesquisa (a fila offline assume).
export interface PollerDeps {
  client: QueryClient
  getTransport: () => TransportState
  subscribe: (cb: () => void) => () => void
  isVisible?: () => boolean
  lastInteraction?: () => number
  now?: () => number
  activeMs?: number
  idleMs?: number
  idleAfterMs?: number
}

export class DegradedPoller {
  private readonly client: QueryClient
  private readonly getTransport: () => TransportState
  private readonly subscribe: (cb: () => void) => () => void
  private readonly isVisible: () => boolean
  private readonly lastInteraction: () => number
  private readonly now: () => number
  private readonly activeMs: number
  private readonly idleMs: number
  private readonly idleAfterMs: number

  private timer: ReturnType<typeof setTimeout> | null = null
  private unsubscribe: (() => void) | null = null

  constructor(deps: PollerDeps) {
    this.client = deps.client
    this.getTransport = deps.getTransport
    this.subscribe = deps.subscribe
    this.isVisible = deps.isVisible ?? (() => (typeof document === 'undefined' ? true : document.visibilityState === 'visible'))
    this.lastInteraction = deps.lastInteraction ?? (() => this.internalLastInteraction)
    this.now = deps.now ?? (() => Date.now())
    this.activeMs = deps.activeMs ?? 20_000
    this.idleMs = deps.idleMs ?? 60_000
    this.idleAfterMs = deps.idleAfterMs ?? 5 * 60_000
  }

  private internalLastInteraction = 0
  private markInteraction = () => {
    this.internalLastInteraction = this.now()
  }

  start(): void {
    if (typeof window !== 'undefined' && !this.hasDefaultInteraction) {
      for (const ev of ['pointerdown', 'keydown', 'visibilitychange']) window.addEventListener(ev, this.markInteraction)
      this.hasDefaultInteraction = true
    }
    this.internalLastInteraction = this.now()
    this.unsubscribe = this.subscribe(() => this.reschedule())
    this.reschedule()
  }

  stop(): void {
    if (this.timer !== null) clearTimeout(this.timer)
    this.timer = null
    this.unsubscribe?.()
    this.unsubscribe = null
    if (this.hasDefaultInteraction && typeof window !== 'undefined') {
      for (const ev of ['pointerdown', 'keydown', 'visibilitychange']) window.removeEventListener(ev, this.markInteraction)
      this.hasDefaultInteraction = false
    }
  }

  private hasDefaultInteraction = false

  // (Re)agenda o próximo tick conforme o estado atual. Fora de `degraded`, para.
  private reschedule(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer)
      this.timer = null
    }
    if (this.getTransport() !== 'degraded') return
    this.timer = setTimeout(() => this.tick(), this.currentInterval())
  }

  private currentInterval(): number {
    const idle = this.now() - this.lastInteraction() >= this.idleAfterMs || !this.isVisible()
    return idle ? this.idleMs : this.activeMs
  }

  private tick(): void {
    this.timer = null
    if (this.getTransport() === 'degraded' && this.isVisible()) {
      void this.client.refetchQueries({ type: 'active' })
    }
    this.reschedule()
  }
}
