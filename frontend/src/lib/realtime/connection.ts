import { createConsumer as railsCreateConsumer } from '@rails/actioncable'
import type { QueryClient } from '@tanstack/react-query'
import { cableTicketsApi } from '../api/endpoints'
import { useRealtimeStore } from '../../store/realtimeStore'
import { keysForEvent, type RealtimeEnvelope } from './eventMap'
import { InvalidationQueue } from './invalidationQueue'

// realtime-collaboration 5.1 / D6.1, D6.8 — o cliente de conexão. Sequência:
// pega o TICKET (Bearer → ticket de 60s), abre o consumer em `/cable?ticket=`,
// e assina o `WorkspaceChannel` do workspace corrente. Na TROCA de workspace,
// descarta a assinatura anterior ANTES de criar a nova (uma assinatura órfã de W1
// continuaria invalidando chaves de um workspace que saiu da tela — §3.10 de
// app-shell-navigation, e a barreira `clear()` de switchWorkspace já correu).
//
// Injetável para teste: `createConsumer`/`fetchTicket` mockados (jsdom não tem
// WebSocket real). O estado de transporte e o `seq` moram no `realtimeStore`.

const WS_URL: string =
  (import.meta as { env?: Record<string, string> }).env?.VITE_WS_URL ||
  window.location.origin.replace(/^http/, 'ws').replace('5173', '3000')

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
  wsUrl?: string
  intervalMs?: number
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
  private readonly wsUrl: string
  private readonly queue: InvalidationQueue

  private consumer: ConsumerLike | null = null
  private subscription: SubscriptionLike | null = null
  private wsId: string | null = null
  // Geração monotônica: uma chamada `connect` mais nova invalida o resultado
  // (assíncrono) de uma anterior — troca rápida W1→W2 não deixa a assinatura de
  // W1 nascer depois do teardown.
  private generation = 0

  constructor(deps: RealtimeClientDeps) {
    this.queryClient = deps.queryClient
    this.createConsumer = deps.createConsumer ?? ((url) => railsCreateConsumer(url) as unknown as ConsumerLike)
    this.fetchTicket = deps.fetchTicket ?? (() => cableTicketsApi.create().then((r) => r.ticket))
    this.wsUrl = deps.wsUrl ?? WS_URL
    this.queue = new InvalidationQueue(this.queryClient, deps.intervalMs)
  }

  // (Re)assina o workspace `wsId`, descartando qualquer assinatura anterior.
  async connect(wsId: string): Promise<void> {
    const gen = ++this.generation
    this.teardown()
    this.wsId = wsId
    useRealtimeStore.getState().setTransport('connecting')

    let ticket: string
    try {
      ticket = await this.fetchTicket()
    } catch {
      if (gen === this.generation) useRealtimeStore.getState().setTransport('offline')
      return
    }
    if (gen !== this.generation) return // trocou de workspace durante o await

    const consumer = this.createConsumer(cableUrl(this.wsUrl, ticket))
    const subscription = consumer.subscriptions.create(
      { channel: 'WorkspaceChannel', workspace_id: wsId },
      {
        connected: () => {
          if (gen === this.generation) useRealtimeStore.getState().setTransport('live')
        },
        disconnected: () => {
          // A máquina de degradação/backoff (8s, 3-em-60s) é do G7; aqui só o
          // básico: caiu → tentando reconectar.
          if (gen === this.generation) useRealtimeStore.getState().setTransport('connecting')
        },
        received: (data: unknown) => {
          if (gen === this.generation) this.onEnvelope(data as RealtimeEnvelope)
        },
      },
    )

    this.consumer = consumer
    this.subscription = subscription
  }

  private onEnvelope(env: RealtimeEnvelope): void {
    // Envelope de outro workspace (assinatura em teardown) é descartado. O
    // descarte do PRÓPRIO eco por `origin_id` é do G6 (precisa do header no axios).
    if (!env || env.workspace_id !== this.wsId) return

    useRealtimeStore.getState().noteSeq(env.workspace_id, env.seq)
    this.queue.enqueue(keysForEvent(env.workspace_id, env))
  }

  disconnect(): void {
    this.generation++
    this.teardown()
    this.wsId = null
    useRealtimeStore.getState().reset()
  }

  private teardown(): void {
    this.queue.clear()
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
