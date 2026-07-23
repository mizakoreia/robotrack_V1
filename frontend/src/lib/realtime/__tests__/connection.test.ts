import { describe, it, expect, vi, beforeEach } from 'vitest'
import type { QueryClient } from '@tanstack/react-query'
import { RealtimeClient } from '../connection'
import { useRealtimeStore } from '../../../store/realtimeStore'
import type { RealtimeEnvelope } from '../eventMap'

// jsdom não tem WebSocket real: o @rails/actioncable é mockado e o consumer é
// injetado (createConsumer/fetchTicket) — testamos a máquina por callbacks.
vi.mock('@rails/actioncable', () => ({ createConsumer: vi.fn() }))

type Mixin = { connected?: () => void; disconnected?: () => void; received?: (d: unknown) => void }

function makeEnv(over: Partial<RealtimeEnvelope>): RealtimeEnvelope {
  return {
    v: 1, seq: 1, workspace_id: 'w1', type: 'task.updated',
    entity: { kind: 'task', id: 't' }, scope: { project_id: 'p', cell_id: 'c', robot_id: 'r' },
    actor_person_id: null, origin_id: null, at: '', ...over,
  }
}

describe('RealtimeClient (5.1)', () => {
  let mixin: Mixin
  let subs: { unsubscribe: ReturnType<typeof vi.fn> }[]
  let params: Record<string, unknown>[]
  let url: string
  let consumer: { subscriptions: { create: ReturnType<typeof vi.fn> }; disconnect: ReturnType<typeof vi.fn> }
  let createConsumer: ReturnType<typeof vi.fn>
  let fetchTicket: () => Promise<string>
  let invalidateQueries: ReturnType<typeof vi.fn>
  let queryClient: QueryClient

  beforeEach(() => {
    useRealtimeStore.getState().reset()
    subs = []
    params = []
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
    invalidateQueries = vi.fn()
    queryClient = { invalidateQueries } as unknown as QueryClient
  })

  const client = () =>
    new RealtimeClient({ queryClient, createConsumer, fetchTicket, wsUrl: 'ws://host/cable', intervalMs: 5 })

  it('pega ticket, abre o consumer em /cable?ticket= e assina o WorkspaceChannel do ws', async () => {
    await client().connect('w1')
    expect(fetchTicket).toHaveBeenCalled()
    expect(url).toContain('ticket=TICKET123')
    expect(params[0]).toEqual({ channel: 'WorkspaceChannel', workspace_id: 'w1' })
  })

  it('connected → live; received → nota o seq e invalida as chaves do envelope', async () => {
    await client().connect('w1')
    mixin.connected!()
    expect(useRealtimeStore.getState().transport).toBe('live')

    mixin.received!(makeEnv({ seq: 5 }))
    expect(useRealtimeStore.getState().lastSeq['w1']).toBe(5)
    await new Promise((r) => setTimeout(r, 20))
    expect(invalidateQueries).toHaveBeenCalledWith(
      expect.objectContaining({ queryKey: ['ws', 'w1', 'overview'], refetchType: 'active' }),
    )
  })

  it('troca de workspace descarta a assinatura anterior antes de assinar a nova', async () => {
    const c = client()
    await c.connect('w1')
    await c.connect('w2')
    expect(subs[0].unsubscribe).toHaveBeenCalled()
    expect(consumer.disconnect).toHaveBeenCalled()
    expect(params[1]).toEqual({ channel: 'WorkspaceChannel', workspace_id: 'w2' })
  })

  it('envelope de outro workspace é descartado (assinatura em teardown)', async () => {
    await client().connect('w1')
    mixin.received!(makeEnv({ workspace_id: 'w2', seq: 9 }))
    await new Promise((r) => setTimeout(r, 20))
    expect(invalidateQueries).not.toHaveBeenCalled()
    expect(useRealtimeStore.getState().lastSeq['w2']).toBeUndefined()
  })

  it('falha ao obter o ticket → transport offline, sem abrir consumer', async () => {
    fetchTicket = vi.fn(async () => {
      throw new Error('sem ticket')
    })
    await client().connect('w1')
    expect(useRealtimeStore.getState().transport).toBe('offline')
    expect(createConsumer).not.toHaveBeenCalled()
  })
})
