import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { IDBFactory } from 'fake-indexeddb'
import { _resetQueueDbSingleton } from '../db'
import { enqueueMutation, markResolved } from '../queue'
import { exportQueue, exportQueueJson, downloadQueueExport } from '../export'
import type { EnqueueInput } from '../types'

// offline-pwa 8.3 — exportação da fila.

const input = (id: string): EnqueueInput => ({
  id,
  kind: 'advance.create',
  resource_uuid: id,
  workspace_id: 'W1',
  method: 'POST',
  url: '/x',
  body: { recorded_at: '2026-07-23T14:03:00.000Z' },
  depends_on: [],
})

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
})

describe('exportQueue (8.3)', () => {
  it('dump inclui mutations e resolved_uuids', async () => {
    await enqueueMutation(input('adv-14h'))
    await markResolved('task-1')

    const dump = await exportQueue(undefined, '2026-07-23T18:00:00.000Z')
    expect(dump.exported_at).toBe('2026-07-23T18:00:00.000Z')
    expect(dump.db_version).toBe(2)
    expect(dump.mutations).toHaveLength(1)
    expect(dump.resolved_uuids).toHaveLength(1)

    const json = await exportQueueJson(undefined, '2026-07-23T18:00:00.000Z')
    expect(JSON.parse(json).mutations[0].id).toBe('adv-14h')
  })

  it('downloadQueueExport monta um blob e dispara o anchor', async () => {
    await enqueueMutation(input('adv-1'))
    const click = vi.fn()
    const anchor = { click } as { click: () => void; href?: string; download?: string }
    const createUrl = vi.fn(() => 'blob:url')
    const revokeUrl = vi.fn()

    await downloadQueueExport({
      createUrl,
      revokeUrl,
      anchor: () => anchor,
      nowIso: '2026-07-23T18:00:00.000Z',
    })

    expect(createUrl).toHaveBeenCalled()
    expect(click).toHaveBeenCalled()
    expect(anchor.download).toBe('robotrack-fila-offline-2026-07-23.json')
    expect(revokeUrl).toHaveBeenCalledWith('blob:url')
  })
})
