import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { IDBFactory } from 'fake-indexeddb'
import { openQueueDb, _resetQueueDbSingleton, quarantineIncompatible, DB_NAME } from '../db'
import {
  enqueueMutation,
  listMutations,
  pruneDone,
  markResolved,
  getResolvedUuids,
  MAX_ITEMS,
} from '../queue'
import type { EnqueueInput, QueuedMutation } from '../types'
import { QueueFullError } from '../types'
import { useOfflineQueueStore } from '../../../store/offlineQueueStore'

// offline-pwa 3.4 — persistência da fila com fake-indexeddb: reabertura, ordem de
// `seq`, poda, teto com rejeição na entrada, quarentena e escopo por workspace.

function input(over: Partial<EnqueueInput> = {}): EnqueueInput {
  return {
    id: over.id ?? `m-${Math.random().toString(36).slice(2)}`,
    kind: over.kind ?? 'robot.create',
    resource_uuid: over.resource_uuid ?? 'R',
    workspace_id: over.workspace_id ?? 'W1',
    method: over.method ?? 'POST',
    url: over.url ?? '/api/v1/robots',
    body: over.body ?? { name: 'Robô' },
    depends_on: over.depends_on ?? [],
    recorded_at: over.recorded_at,
  }
}

beforeEach(async () => {
  // Zera o IndexedDB entre casos (fake-indexeddb: nova fábrica global).
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
})

describe('enqueue + persistência (3.2/3.4)', () => {
  it('atribui seq monotônico e sobrevive à reabertura', async () => {
    await enqueueMutation(input({ id: 'a' }))
    await enqueueMutation(input({ id: 'b' }))
    await enqueueMutation(input({ id: 'c' }))

    // Reabre "do zero" (novo singleton, MESMO backing store).
    _resetQueueDbSingleton()
    const items = await listMutations('W1')
    expect(items.map((m) => m.id)).toEqual(['a', 'b', 'c'])
    expect(items.map((m) => m.seq)).toEqual([1, 2, 3])
  })

  it('carimba recorded_at no enfileiramento (D8) com o relógio injetado', async () => {
    const clock = () => Date.parse('2026-07-23T14:03:00Z')
    const m = await enqueueMutation(input({ id: 'x' }), { clock })
    expect(m.recorded_at).toBe('2026-07-23T14:03:00.000Z')
  })

  it('respeita recorded_at explícito quando fornecido', async () => {
    const m = await enqueueMutation(input({ id: 'y', recorded_at: '2020-01-01T00:00:00.000Z' }))
    expect(m.recorded_at).toBe('2020-01-01T00:00:00.000Z')
  })
})

describe('teto e poda (3.3)', () => {
  it('poda itens done e reaceita novas mutations (300 após drenar 200 de 500 seria a lógica)', async () => {
    const db = await openQueueDb()
    // 5 itens; marca 2 como done manualmente.
    for (const id of ['a', 'b', 'c', 'd', 'e']) await enqueueMutation(input({ id }), { db })
    const tx = db.transaction('mutations', 'readwrite')
    for (const id of ['a', 'b']) {
      const rec = (await tx.store.get(id)) as QueuedMutation
      await tx.store.put({ ...rec, state: 'done' })
    }
    await tx.done

    const pruned = await pruneDone(db)
    expect(pruned).toBe(2)
    expect((await listMutations('W1')).map((m) => m.id)).toEqual(['c', 'd', 'e'])
  })

  it('a 501ª é REJEITADA e o item mais antigo NÃO é descartado (D7-12)', async () => {
    const db = await openQueueDb()
    for (let i = 0; i < MAX_ITEMS; i++) await enqueueMutation(input({ id: `m${i}` }), { db })

    await expect(enqueueMutation(input({ id: 'overflow' }), { db })).rejects.toBeInstanceOf(QueueFullError)

    const items = await listMutations('W1')
    expect(items).toHaveLength(MAX_ITEMS)
    expect(items[0].id).toBe('m0') // o mais antigo continua lá
    expect(items.some((m) => m.id === 'overflow')).toBe(false)
  })
})

describe('resolved_uuids (D7-4)', () => {
  it('persiste e lê o conjunto de uuids confirmados', async () => {
    await markResolved('R')
    await markResolved('T')
    const set = await getResolvedUuids()
    expect(set.has('R')).toBe(true)
    expect(set.has('T')).toBe(true)
    expect(set.has('Z')).toBe(false)
  })
})

describe('quarentena de item irreconhecível (3.1)', () => {
  it('marca failed "incompatível" sem apagar', async () => {
    const db = await openQueueDb()
    // Grava um registro de "esquema anterior" cru, sem os campos estruturais.
    const tx = db.transaction('mutations', 'readwrite')
    await tx.store.put({ id: 'legado', payload: 'algo antigo' } as unknown as QueuedMutation)
    await tx.done

    const n = await quarantineIncompatible(db)
    expect(n).toBe(1)

    const rec = await db.get('mutations', 'legado')
    expect(rec?.state).toBe('failed')
    expect(rec?.last_error).toContain('incompatível')
    // NUNCA apagado: o conteúdo continua recuperável.
    expect(await db.count('mutations')).toBe(1)
  })
})

describe('projeção do store escopada por workspace (3.3/D9)', () => {
  it('a fila de W1 não aparece na visão de W2', async () => {
    await enqueueMutation(input({ id: 'w1a', workspace_id: 'W1' }))
    await enqueueMutation(input({ id: 'w2a', workspace_id: 'W2' }))

    await useOfflineQueueStore.getState().setWorkspace('W1')
    expect(useOfflineQueueStore.getState().mutations.map((m) => m.id)).toEqual(['w1a'])

    await useOfflineQueueStore.getState().setWorkspace('W2')
    expect(useOfflineQueueStore.getState().mutations.map((m) => m.id)).toEqual(['w2a'])
  })
})
