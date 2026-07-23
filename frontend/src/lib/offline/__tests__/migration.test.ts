import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { openDB } from 'idb'
import { IDBFactory } from 'fake-indexeddb'
import { openQueueDb, _resetQueueDbSingleton, quarantineIncompatible, DB_NAME } from '../db'
import { listMutations } from '../queue'
import { exportQueue } from '../export'
import type { QueuedMutation } from '../types'

// offline-pwa 8.3/8.4 — migração de esquema VERSIONADA (v1→v2) e o backup que a
// precede. Abrir uma versão nova sobre uma base antiga não perde item pendente.

const validMutation = (id: string): QueuedMutation =>
  ({
    id,
    seq: 1,
    kind: 'advance.create',
    resource_uuid: id,
    workspace_id: 'W1',
    method: 'POST',
    url: '/x',
    body: { recorded_at: '2026-07-23T14:03:00.000Z' },
    depends_on: [],
    recorded_at: '2026-07-23T14:03:00.000Z',
    state: 'enqueued',
    attempts: 0,
    next_attempt_at: null,
    last_error: null,
  }) as QueuedMutation

// Recria o esquema v1 (sem o store `leader`, que só existe em v2).
async function openV1() {
  return openDB(DB_NAME, 1, {
    upgrade(db) {
      const m = db.createObjectStore('mutations', { keyPath: 'id' })
      m.createIndex('by_state_and_seq', ['state', 'seq'])
      m.createIndex('by_workspace', 'workspace_id')
      db.createObjectStore('resolved_uuids', { keyPath: 'uuid' })
      db.createObjectStore('meta', { keyPath: 'key' })
    },
  })
}

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
})

describe('migração v1 → v2 (8.4)', () => {
  it('preserva itens pendentes e cria o store leader', async () => {
    const v1 = await openV1()
    await v1.put('mutations', validMutation('pendente-14h'))
    v1.close()

    // Abre na versão corrente (v2): a migração roda.
    const v2 = await openQueueDb()
    expect(v2.version).toBe(2)
    expect([...v2.objectStoreNames]).toContain('leader') // store novo aditivo

    const items = await listMutations('W1')
    expect(items.map((m) => m.id)).toEqual(['pendente-14h']) // NADA perdido
    expect(items[0].recorded_at).toBe('2026-07-23T14:03:00.000Z')
  })

  it('o backup (8.3) captura o conteúdo ANTES de qualquer quarentena', async () => {
    const v1 = await openV1()
    await v1.put('mutations', validMutation('avanco-14h'))
    // Item de esquema anterior, irreconhecível.
    await v1.put('mutations', { id: 'legado' } as unknown as QueuedMutation)
    v1.close()

    const db = await openQueueDb()

    // Backup exportável recupera TUDO, inclusive o avanço das 14h.
    const backup = await exportQueue(db, '2026-07-23T18:00:00.000Z')
    expect(backup.db_version).toBe(2)
    expect(backup.mutations.map((m) => (m as QueuedMutation).id).sort()).toEqual(['avanco-14h', 'legado'])

    // A quarentena marca o irreconhecível como failed, sem apagar.
    expect(await quarantineIncompatible(db)).toBe(1)
    const legado = await db.get('mutations', 'legado')
    expect(legado?.state).toBe('failed')
    expect(await db.count('mutations')).toBe(2) // nada apagado
  })
})
