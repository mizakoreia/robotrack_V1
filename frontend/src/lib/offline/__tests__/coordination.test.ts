import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { IDBFactory } from 'fake-indexeddb'
import { openQueueDb, _resetQueueDbSingleton } from '../db'
import { enqueueMutation, listMutations } from '../queue'
import { drainQueue, _resetDrainGuard, type SendResult } from '../drain'
import { runAsLeader, claimLeaderFallback, LEADER_TTL_MS } from '../leader'
import { createQueueBroadcast, QUEUE_CHANNEL } from '../broadcast'
import type { EnqueueInput, QueuedMutation } from '../types'

// offline-pwa 6.1/6.2/6.3 — coordenação entre abas.

function input(over: Partial<EnqueueInput>): EnqueueInput {
  return {
    id: over.id!,
    kind: over.kind ?? 'robot.create',
    resource_uuid: over.resource_uuid ?? over.id!,
    workspace_id: 'W1',
    method: 'POST',
    url: '/api/v1/robots',
    body: {},
    depends_on: over.depends_on ?? [],
  }
}

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
  _resetDrainGuard()
  // Força o caminho de fallback (WebKit sem Web Locks) para determinismo.
  delete (navigator as { locks?: unknown }).locks
})

describe('eleição de líder por fallback (6.2)', () => {
  it('duas abas disputando: só uma se elege na janela', async () => {
    const db = await openQueueDb()
    const a = await claimLeaderFallback(db, 'A', 1000)
    const b = await claimLeaderFallback(db, 'B', 1000)
    expect(a).toBe(true)
    expect(b).toBe(false) // A é o líder; B não rouba
  })

  it('o líder renova; ninguém mais assume antes de expirar', async () => {
    const db = await openQueueDb()
    await claimLeaderFallback(db, 'A', 1000)
    expect(await claimLeaderFallback(db, 'A', 2000)).toBe(true) // A renova
    expect(await claimLeaderFallback(db, 'B', 2000)).toBe(false)
  })

  it('expirado → outra aba assume', async () => {
    const db = await openQueueDb()
    await claimLeaderFallback(db, 'A', 1000)
    expect(await claimLeaderFallback(db, 'B', 1000 + LEADER_TTL_MS + 1)).toBe(true)
  })
})

describe('duas instâncias, uma requisição por mutation (6.3)', () => {
  it('o líder drena tudo; a não-líder não envia nada', async () => {
    const db = await openQueueDb()
    for (const id of ['R', 'S', 'T']) await enqueueMutation(input({ id }), { db })

    const send = vi.fn(async (): Promise<SendResult> => ({ ok: true, status: 200 }))
    const runner = (tabId: string) =>
      runAsLeader(() => drainQueue({ probe: async () => true, send, now: () => 0 }), { db, tabId, now: () => 0 })

    const [a, b] = await Promise.all([runner('A'), runner('B')])

    // Exatamente uma aba drenou; o servidor recebeu 3 chamadas, não 6.
    expect(a.ran !== b.ran).toBe(true)
    expect(send).toHaveBeenCalledTimes(3)
    expect((await listMutations('W1')).every((m: QueuedMutation) => m.state === 'done')).toBe(true)
  })
})

describe('broadcast entre abas (6.2)', () => {
  it('post numa aba chega às assinantes das outras', () => {
    // BroadcastChannel existe no jsdom; duas instâncias no mesmo canal se falam.
    const tabA = createQueueBroadcast()
    const tabB = createQueueBroadcast()
    const received: string[] = []
    tabB.subscribe((m) => received.push(m))

    tabA.post('changed')

    return new Promise<void>((resolve) => {
      setTimeout(() => {
        expect(received).toEqual(['changed'])
        tabA.close()
        tabB.close()
        resolve()
      }, 10)
    })
  })

  it('degrada para no-op sem BroadcastChannel (WebKit)', () => {
    const noop = createQueueBroadcast({ ctor: undefined })
    void QUEUE_CHANNEL
    expect(() => {
      noop.post('changed')
      const un = noop.subscribe(() => {})
      un()
      noop.close()
    }).not.toThrow()
  })
})
