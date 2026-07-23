import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { IDBFactory } from 'fake-indexeddb'
import { _resetQueueDbSingleton } from '../db'
import { enqueueMutation, listMutations, markResolved } from '../queue'
import { drainQueue, seedResolvedFromServer, _resetDrainGuard, type SendResult } from '../drain'
import { eligibleMutations, nextEligible } from '../eligibility'
import type { EnqueueInput, QueuedMutation } from '../types'

// offline-pwa 4.1/4.2/4.4 — grafo de dependência e drenagem sequencial.

function input(over: Partial<EnqueueInput>): EnqueueInput {
  return {
    id: over.id!,
    kind: over.kind ?? 'robot.create',
    resource_uuid: over.resource_uuid ?? over.id!,
    workspace_id: over.workspace_id ?? 'W1',
    method: over.method ?? 'POST',
    url: over.url ?? '/api/v1/robots',
    body: over.body ?? {},
    depends_on: over.depends_on ?? [],
    recorded_at: over.recorded_at,
  }
}

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
  _resetDrainGuard()
})

describe('elegibilidade (4.1)', () => {
  it('pula o não elegível sem bloquear o seq seguinte', async () => {
    const items: QueuedMutation[] = [
      { seq: 2, state: 'enqueued', depends_on: ['R'] } as QueuedMutation,
      { seq: 4, state: 'enqueued', depends_on: [] } as QueuedMutation,
    ]
    const resolved = new Set<string>()
    expect(nextEligible(items, resolved)?.seq).toBe(4) // seq 4 sobe, seq 2 espera R
    await markResolved('R')
    expect(eligibleMutations(items, new Set(['R'])).map((m) => m.seq)).toEqual([2, 4])
  })
})

describe('drenagem — cenário canônico R→T→A (4.4)', () => {
  it('envia na ordem correta, respeitando o grafo, uma em voo', async () => {
    // Tudo offline: robô R, tarefa T (dep R), avanço A (dep T).
    await enqueueMutation(input({ id: 'R', kind: 'robot.create', resource_uuid: 'R', depends_on: [] }))
    await enqueueMutation(input({ id: 'T', kind: 'task.create', resource_uuid: 'T', depends_on: ['R'] }))
    await enqueueMutation(input({ id: 'A', kind: 'advance.create', resource_uuid: 'A', depends_on: ['T'] }))

    const order: string[] = []
    let inFlight = 0
    let maxInFlight = 0
    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => {
      inFlight += 1
      maxInFlight = Math.max(maxInFlight, inFlight)
      order.push(m.id)
      await Promise.resolve()
      inFlight -= 1
      return { ok: true, status: 201 }
    })

    const outcome = await drainQueue({ probe: async () => true, send })

    expect(order).toEqual(['R', 'T', 'A']) // FK do servidor rejeitaria qualquer inversão
    expect(maxInFlight).toBe(1) // uma requisição em voo por vez
    expect(outcome.sent).toBe(3)
    // Todas as três resolvidas: nada sobra na fila para drenar.
    const left = (await listMutations('W1')).filter((m) => m.state !== 'done')
    expect(left).toHaveLength(0)
  })

  it('sonda falha → não envia nada (porteiro)', async () => {
    await enqueueMutation(input({ id: 'R', resource_uuid: 'R' }))
    const send = vi.fn()
    const outcome = await drainQueue({ probe: async () => false, send })
    expect(send).not.toHaveBeenCalled()
    expect(outcome.skipped).toBe(true)
  })
})

describe('resolved_uuids semeado por leitura do servidor (4.2/D1)', () => {
  it('tarefa contra um robô que já existia no servidor é elegível sem robot.create', async () => {
    // O robô R já existe no servidor (cliente leu antes de ficar offline).
    await seedResolvedFromServer(['R'])
    await enqueueMutation(input({ id: 'T', kind: 'task.create', resource_uuid: 'T', depends_on: ['R'] }))

    const order: string[] = []
    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => {
      order.push(m.id)
      return { ok: true, status: 201 }
    })
    await drainQueue({ probe: async () => true, send })
    expect(order).toEqual(['T']) // elegível sem nenhuma mutation de criação de robô
  })
})

describe('erro para o laço sem girar (G4; G5 refina)', () => {
  it('devolve o item a enfileirado com attempts++ e para', async () => {
    await enqueueMutation(input({ id: 'R', resource_uuid: 'R' }))
    const send = vi.fn(async (): Promise<SendResult> => ({ ok: false, status: 500 }))
    const outcome = await drainQueue({ probe: async () => true, send })
    expect(send).toHaveBeenCalledTimes(1) // não gira
    expect(outcome.sent).toBe(0)
    const [r] = await listMutations('W1')
    expect(r.state).toBe('enqueued')
    expect(r.attempts).toBe(1)
    expect(r.last_error).toContain('500')
  })
})
