import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import type { QueryClient } from '@tanstack/react-query'
import { RealtimeClient, backoffDelay, type RealtimeClientDeps } from '../connection'
import { useRealtimeStore } from '../../../store/realtimeStore'
import type { RealtimeEnvelope } from '../eventMap'
import type { WorkspaceSyncResult } from '../../api/endpoints'

// jsdom não tem WebSocket real: o @rails/actioncable é mockado e o consumer é
// injetado — testamos a máquina (transporte, backoff, reconciliação) por callbacks.
vi.mock('@rails/actioncable', () => ({ createConsumer: vi.fn() }))

type Mixin = { connected?: () => void; disconnected?: () => void; received?: (d: unknown) => void }

function makeEnv(over: Partial<RealtimeEnvelope>): RealtimeEnvelope {
  return {
    v: 1, seq: 1, workspace_id: 'w1', type: 'task.updated',
    entity: { kind: 'task', id: 't' }, scope: { project_id: 'p', cell_id: 'c', robot_id: 'r' },
    actor_person_id: null, origin_id: null, at: '', ...over,
  }
}

describe('RealtimeClient (5.1 + 7.1/7.4)', () => {
  let mixin: Mixin
  let subs: { unsubscribe: ReturnType<typeof vi.fn> }[]
  let params: Record<string, unknown>[]
  let url: string
  let consumer: { subscriptions: { create: ReturnType<typeof vi.fn> }; disconnect: ReturnType<typeof vi.fn> }
  let createConsumer: ReturnType<typeof vi.fn>
  let fetchTicket: () => Promise<string>
  let fetchSync: ReturnType<typeof vi.fn>
  let invalidateQueries: ReturnType<typeof vi.fn>
  let queryClient: QueryClient
  let clients: RealtimeClient[]

  beforeEach(() => {
    useRealtimeStore.getState().reset()
    subs = []
    params = []
    clients = []
    consumer = {
      subscriptions: {
        create: vi.fn((p: Record<string, unknown>, m: Mixin) => {
          params.push(p)
          mixin = m
          const s = { unsubscribe: vi.fn() }
          subs.push(s)
          return s
        }),
      },
      disconnect: vi.fn(),
    }
    createConsumer = vi.fn((u: string) => {
      url = u
      return consumer
    })
    fetchTicket = vi.fn(async () => 'TICKET123')
    fetchSync = vi.fn(async (): Promise<WorkspaceSyncResult> => ({ current_seq: 0, gap: false, entity_kinds: [] }))
    invalidateQueries = vi.fn()
    queryClient = {
      invalidateQueries,
      getMutationCache: () => ({ getAll: () => [], subscribe: () => () => {} }),
    } as unknown as QueryClient
  })

  afterEach(() => clients.forEach((c) => c.disconnect()))

  function client(over: Partial<RealtimeClientDeps> = {}) {
    const c = new RealtimeClient({
      queryClient, createConsumer, fetchTicket, fetchSync,
      wsUrl: 'ws://host/cable', intervalMs: 5, welcomeMs: 100_000, random: () => 0.5, ...over,
    })
    clients.push(c)
    return c
  }

  it('backoffDelay cresce 5s→15s→45s→teto 2min (com jitter ±20%)', () => {
    const mid = (a: number) => backoffDelay(a, () => 0.5) // jitter zero no meio
    expect(mid(0)).toBe(5_000)
    expect(mid(1)).toBe(15_000)
    expect(mid(2)).toBe(45_000)
    expect(mid(9)).toBe(120_000)
    expect(backoffDelay(0, () => 1)).toBeLessThanOrEqual(6_000) // +20% máx
    expect(backoffDelay(0, () => 0)).toBeGreaterThanOrEqual(4_000) // -20% máx
  })

  it('pega ticket, abre o consumer em /cable?ticket= e assina o WorkspaceChannel', async () => {
    await client().connect('w1')
    expect(fetchTicket).toHaveBeenCalled()
    expect(url).toContain('ticket=TICKET123')
    expect(params[0]).toEqual({ channel: 'WorkspaceChannel', workspace_id: 'w1' })
  })

  it('connected → live; e reconcilia por /sync (7.4)', async () => {
    await client().connect('w1')
    mixin.connected!()
    expect(useRealtimeStore.getState().transport).toBe('live')
    expect(fetchSync).toHaveBeenCalledWith('w1', 0)
  })

  it('reconciliação com gap invalida a subárvore inteira (queda longa)', async () => {
    fetchSync.mockResolvedValueOnce({ current_seq: 12, gap: true, entity_kinds: [] })
    await client().connect('w1')
    mixin.connected!()
    await new Promise((r) => setTimeout(r, 20))
    expect(invalidateQueries).toHaveBeenCalledWith(expect.objectContaining({ queryKey: ['ws', 'w1'] }))
    expect(useRealtimeStore.getState().lastSeq['w1']).toBe(12)
  })

  it('received → nota o seq e invalida as chaves do envelope', async () => {
    await client().connect('w1')
    mixin.received!(makeEnv({ seq: 5 }))
    expect(useRealtimeStore.getState().lastSeq['w1']).toBe(5)
    await new Promise((r) => setTimeout(r, 20))
    expect(invalidateQueries).toHaveBeenCalledWith(
      expect.objectContaining({ queryKey: ['ws', 'w1', 'overview'], refetchType: 'active' }),
    )
  })

  it('descarta o PRÓPRIO eco por origin_id (6.1)', async () => {
    await client().connect('w1')
    const mine = useRealtimeStore.getState().originId
    mixin.received!(makeEnv({ seq: 7, origin_id: mine }))
    expect(useRealtimeStore.getState().lastSeq['w1']).toBe(7) // seq avança
    await new Promise((r) => setTimeout(r, 20))
    expect(invalidateQueries).not.toHaveBeenCalled() // mas não refetcha
  })

  it('sem `welcome` em 8s → degraded (proxy engolindo o Upgrade)', async () => {
    await client({ welcomeMs: 15 }).connect('w1')
    // não chamamos connected
    await new Promise((r) => setTimeout(r, 40))
    expect(useRealtimeStore.getState().transport).toBe('degraded')
  })

  it('3 quedas em 60s → degraded', async () => {
    await client().connect('w1')
    mixin.disconnected!()
    expect(useRealtimeStore.getState().transport).not.toBe('degraded')
    mixin.disconnected!()
    mixin.disconnected!()
    expect(useRealtimeStore.getState().transport).toBe('degraded')
  })

  it('troca de workspace descarta a assinatura anterior antes de assinar a nova', async () => {
    const c = client()
    await c.connect('w1')
    await c.connect('w2')
    expect(subs[0].unsubscribe).toHaveBeenCalled()
    expect(params[1]).toEqual({ channel: 'WorkspaceChannel', workspace_id: 'w2' })
  })

  it('offline (sem rede) → transport offline, sem abrir consumer', async () => {
    await client({ isOnline: () => false }).connect('w1')
    expect(useRealtimeStore.getState().transport).toBe('offline')
    expect(createConsumer).not.toHaveBeenCalled()
  })

  it('falha ao obter o ticket → degraded (cai para polling), sem consumer', async () => {
    await client({ fetchTicket: vi.fn(async () => { throw new Error('sem ticket') }) }).connect('w1')
    expect(useRealtimeStore.getState().transport).toBe('degraded')
    expect(createConsumer).not.toHaveBeenCalled()
  })
})
