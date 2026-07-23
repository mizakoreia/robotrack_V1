import { createConsumer as railsCreateConsumer } from '@rails/actioncable'
import type { QueryClient } from '@tanstack/react-query'
import { cableTicketsApi, workspacesApi, type WorkspaceSyncResult } from '../api/endpoints'
import { useRealtimeStore } from '../../store/realtimeStore'
import { keysForEvent, type RealtimeEnvelope } from './eventMap'
import { InvalidationQueue } from './invalidationQueue'
import { InvalidationGate, type OfflinePendingProbe } from './invalidationGate'
import { reconcileKeys } from './reconcile'

// realtime-collaboration 5.1 + 7.1/7.4 / D6.1, D6.6, D6.8 — o cliente de conexão.
//
// Ticket (Bearer→ticket 60s) → consumer em `/cable?ticket=` → assina o
// WorkspaceChannel. O ticket é de USO ÚNICO, então NÃO dá para deixar o
// ActionCable auto-reconectar com a mesma URL (ticket morto): na queda, encerramos
// o consumer e reconectamos com um ticket NOVO, em backoff (5s,15s,45s, teto 2min)
// com jitter, em paralelo ao polling. Sem `welcome` em 8s ou 3 falhas em 60s →
// `degraded`. Ao (re)conectar, reconcilia por `/sync?since=<seq>` (7.4).

const WS_URL: string =
  (import.meta as { env?: Record<string, string> }).env?.VITE_WS_URL ||
  window.location.origin.replace(/^http/, 'ws').replace('5173', '3000')

const BACKOFF_MS = [5_000, 15_000, 45_000, 120_000]
const WELCOME_TIMEOUT_MS = 8_000
const FAILURE_WINDOW_MS = 60_000
const FAILURE_THRESHOLD = 3

export function backoffDelay(attempt: number, random: () => number): number {
  const base = BACKOFF_MS[Math.min(attempt, BACKOFF_MS.length - 1)]
  const jitter = base * 0.2 * (random() * 2 - 1) // ±20%
  return Math.max(1_000, Math.round(base + jitter))
}

export interface SubscriptionLike {
  unsubscribe: () => void
}
export interface ConsumerLike {
  subscriptions: {
    create: (
      params: Record<string, unknown>,
      mixin: { connected?: () => void; disconnected?: () => void; received?: (data: unknown) => void },
    ) => SubscriptionLike
  }
  disconnect: () => void
}

export interface RealtimeClientDeps {
  queryClient: QueryClient
  createConsumer?: (url: string) => ConsumerLike
  fetchTicket?: () => Promise<string>
  fetchSync?: (wsId: string, since: number) => Promise<WorkspaceSyncResult>
  wsUrl?: string
  intervalMs?: number
  offlineProbe?: OfflinePendingProbe
  welcomeMs?: number
  random?: () => number
  now?: () => number
  isOnline?: () => boolean
}

function cableUrl(base: string, ticket: string): string {
  const endpoint = base.endsWith('/cable') ? base : `${base.replace(/\/+$/, '')}/cable`
  const sep = endpoint.includes('?') ? '&' : '?'
  return `${endpoint}${sep}ticket=${encodeURIComponent(ticket)}`
}

export class RealtimeClient {
  private readonly queryClient: QueryClient
  private readonly createConsumer: (url: string) => ConsumerLike
  private readonly fetchTicket: () => Promise<string>
  private readonly fetchSync: (wsId: string, since: number) => Promise<WorkspaceSyncResult>
  private readonly wsUrl: string
  private readonly queue: InvalidationQueue
  private readonly welcomeMs: number
  private readonly random: () => number
  private readonly now: () => number
  private readonly isOnline: () => boolean

  private consumer: ConsumerLike | null = null
  private subscription: SubscriptionLike | null = null
  private wsId: string | null = null
  private generation = 0
  private welcomeTimer: ReturnType<typeof setTimeout> | null = null
  private retryTimer: ReturnType<typeof setTimeout> | null = null
  private retryAttempt = 0
  private failures: number[] = []

  constructor(deps: RealtimeClientDeps) {
    this.queryClient = deps.queryClient
    this.createConsumer = deps.createConsumer ?? ((url) => railsCreateConsumer(url) as unknown as ConsumerLike)
    this.fetchTicket = deps.fetchTicket ?? (() => cableTicketsApi.create().then((r) => r.ticket))
    this.fetchSync = deps.fetchSync ?? ((wsId, since) => workspacesApi.sync(wsId, since))
    this.wsUrl = deps.wsUrl ?? WS_URL
    this.welcomeMs = deps.welcomeMs ?? WELCOME_TIMEOUT_MS
    this.random = deps.random ?? Math.random
    this.now = deps.now ?? (() => Date.now())
    this.isOnline = deps.isOnline ?? (() => (typeof navigator === 'undefined' ? true : navigator.onLine))
    const gate = new InvalidationGate(this.queryClient, deps.offlineProbe)
    this.queue = new InvalidationQueue(this.queryClient, {
      intervalMs: deps.intervalMs,
      gate,
      onCeilingBreach: () => useRealtimeStore.getState().setSynced(false),
      onFullyDrained: () => useRealtimeStore.getState().setSynced(true),
    })
  }

  async connect(wsId: string): Promise<void> {
    const gen = ++this.generation
    this.teardownConsumer()
    this.clearTimers()
    this.wsId = wsId

    if (!this.isOnline()) {
      useRealtimeStore.getState().setTransport('offline')
      this.scheduleReconnect(wsId, gen)
      return
    }
    useRealtimeStore.getState().setTransport('connecting')

    // Sem `welcome` em 8s → degraded (o proxy pode estar engolindo o Upgrade),
    // seguindo a reconexão em paralelo ao polling.
    this.welcomeTimer = setTimeout(() => {
      if (gen !== this.generation) return
      useRealtimeStore.getState().setTransport('degraded')
      this.scheduleReconnect(wsId, gen)
    }, this.welcomeMs)

    let ticket: string
    try {
      ticket = await this.fetchTicket()
    } catch {
      if (gen === this.generation) {
        useRealtimeStore.getState().setTransport('degraded')
        this.clearWelcome()
        this.scheduleReconnect(wsId, gen)
      }
      return
    }
    if (gen !== this.generation) return

    const consumer = this.createConsumer(cableUrl(this.wsUrl, ticket))
    const subscription = consumer.subscriptions.create(
      { channel: 'WorkspaceChannel', workspace_id: wsId },
      {
        connected: () => {
          if (gen === this.generation) this.onConnected(wsId)
        },
        disconnected: () => {
          if (gen === this.generation) this.onDisconnected(wsId, gen)
        },
        received: (data: unknown) => {
          if (gen === this.generation) this.onEnvelope(data as RealtimeEnvelope)
        },
      },
    )
    this.consumer = consumer
    this.subscription = subscription
  }

  private onConnected(wsId: string): void {
    this.clearWelcome()
    this.clearRetry()
    this.retryAttempt = 0
    this.failures = []
    useRealtimeStore.getState().setTransport('live')
    void this.reconcile(wsId)
  }

  private onDisconnected(wsId: string, gen: number): void {
    this.clearWelcome()
    const t = this.now()
    this.failures = this.failures.filter((ts) => t - ts < FAILURE_WINDOW_MS)
    this.failures.push(t)

    if (!this.isOnline()) {
      useRealtimeStore.getState().setTransport('offline')
    } else if (this.failures.length >= FAILURE_THRESHOLD) {
      useRealtimeStore.getState().setTransport('degraded')
    }
    // Encerra o consumer (evita o auto-retry do ActionCable com o ticket morto) e
    // reconecta com ticket novo, em backoff.
    this.teardownConsumer()
    this.scheduleReconnect(wsId, gen)
  }

  // Reconciliação por lacuna (7.4): pergunta ao servidor o que se perdeu desde o
  // último `seq` e invalida conforme. `since == current_seq` → nada (sem refetch).
  private async reconcile(wsId: string): Promise<void> {
    const since = useRealtimeStore.getState().lastSeq[wsId] ?? 0
    try {
      const result = await this.fetchSync(wsId, since)
      if (this.wsId !== wsId) return
      useRealtimeStore.getState().noteSeq(wsId, result.current_seq)
      const keys = reconcileKeys(wsId, result)
      if (keys.length) this.queue.enqueue(keys)
    } catch {
      /* best-effort: a próxima reconexão tenta de novo */
    }
  }

  private scheduleReconnect(wsId: string, gen: number): void {
    this.clearRetry()
    const delay = backoffDelay(this.retryAttempt, this.random)
    this.retryAttempt++
    this.retryTimer = setTimeout(() => {
      if (gen === this.generation) void this.connect(wsId)
    }, delay)
  }

  private onEnvelope(env: RealtimeEnvelope): void {
    if (!env || env.workspace_id !== this.wsId) return
    useRealtimeStore.getState().noteSeq(env.workspace_id, env.seq)
    if (env.origin_id && env.origin_id === useRealtimeStore.getState().originId) return
    this.queue.enqueue(keysForEvent(env.workspace_id, env))
  }

  disconnect(): void {
    this.generation++
    this.teardownConsumer()
    this.clearTimers()
    this.retryAttempt = 0
    this.failures = []
    this.wsId = null
    this.queue.clear()
    useRealtimeStore.getState().reset()
  }

  private clearWelcome(): void {
    if (this.welcomeTimer !== null) clearTimeout(this.welcomeTimer)
    this.welcomeTimer = null
  }
  private clearRetry(): void {
    if (this.retryTimer !== null) clearTimeout(this.retryTimer)
    this.retryTimer = null
  }
  private clearTimers(): void {
    this.clearWelcome()
    this.clearRetry()
  }

  private teardownConsumer(): void {
    try {
      this.subscription?.unsubscribe()
    } catch {
      /* noop */
    }
    try {
      this.consumer?.disconnect()
    } catch {
      /* noop */
    }
    this.subscription = null
    this.consumer = null
  }
}

// Singleton do runtime (a instância de teste é criada com deps próprias).
let client: RealtimeClient | null = null

export function initRealtime(queryClient: QueryClient): RealtimeClient {
  client ??= new RealtimeClient({ queryClient })
  return client
}

export function getRealtimeClient(): RealtimeClient | null {
  return client
}
