import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { IDBFactory } from 'fake-indexeddb'
import { _resetQueueDbSingleton } from '../db'
import { seedResolvedFromServer } from '../drain'
import { drainQueue, _resetDrainGuard, type SendResult } from '../drain'
import { enqueueAdvance } from '../producers'
import { listMutations } from '../queue'
import type { QueuedMutation } from '../types'

// offline-pwa 8.5 — as provas de ponta a ponta (nível integração; o harness
// Playmeter/WebKit é handoff para quality-and-accessibility, ver EXECUCAO).

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
  _resetDrainGuard()
})

describe('honestidade temporal (D8)', () => {
  it('avanço confirmado offline às 14:03 e enviado às 17:41: trilha mostra 14:03, created_at do servidor 17:41', async () => {
    // A tarefa já existe no servidor (lida antes de ficar offline).
    await seedResolvedFromServer(['task-1'])

    // 14:03 — o engenheiro confirma o avanço offline. `recorded_at` é carimbado AQUI.
    const RECORDED = '2026-07-23T14:03:00.000Z'
    await enqueueAdvance({
      advanceId: 'adv-1',
      taskId: 'task-1',
      robotId: 'robot-1',
      workspaceId: 'W1',
      progress: 60,
      recordedAt: RECORDED,
    })

    const item = (await listMutations('W1'))[0]
    expect(item.recorded_at).toBe(RECORDED)

    // 17:41 — a rede volta e o servidor processa. Ele guarda o recorded_at do
    // cliente e carimba o PRÓPRIO created_at.
    const SERVER_CREATED = '2026-07-23T17:41:00.000Z'
    let trailRow: { recorded_at: string; created_at: string } | null = null
    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => {
      const body = m.body as { recorded_at: string }
      trailRow = { recorded_at: body.recorded_at, created_at: SERVER_CREATED }
      return { ok: true, status: 201 }
    })

    await drainQueue({ probe: async () => true, send, now: () => Date.parse(SERVER_CREATED) })

    expect(send).toHaveBeenCalledTimes(1)
    // A trilha e o relatório mostram o recorded_at (14:03); o created_at é do envio (17:41).
    expect(trailRow!.recorded_at).toBe('2026-07-23T14:03:00.000Z')
    expect(trailRow!.created_at).toBe('2026-07-23T17:41:00.000Z')
    expect((await listMutations('W1'))[0].state).toBe('done')
  })
})

describe('honestidade de deploy (§4.3): build A não é servido do cache após publicar B', () => {
  const ORIGIN = 'https://app.robotrack.test'
  const SW_SOURCE = readFileSync(resolve(__dirname, '../../../../public/sw.js'), 'utf8')

  function loadSw(cacheName: string, fetchImpl: typeof fetch) {
    const handlers: Record<string, (e: unknown) => void> = {}
    const store = new Map<string, Response>()
    const cache = {
      put: vi.fn(async (req: { url: string }, res: Response) => store.set(req.url, res)),
      match: vi.fn(async (req: { url: string } | string) =>
        store.get(typeof req === 'string' ? req : req.url),
      ),
    }
    const caches = { open: vi.fn(async () => cache), keys: vi.fn(async () => []), delete: vi.fn() }
    const self = {
      location: { origin: ORIGIN },
      addEventListener: (t: string, h: (e: unknown) => void) => (handlers[t] = h),
      skipWaiting: vi.fn(),
      clients: { claim: vi.fn(async () => {}) },
    }
    // Injeta o CACHE_NAME do "build" corrente.
    new Function('self', 'caches', 'fetch', SW_SOURCE.replace('__CACHE_NAME__', cacheName))(self, caches, fetchImpl)
    return { handlers, cache, store }
  }

  it('network-first serve o asset do build B (rede) e o grava, não o do cache do build A', async () => {
    // Build B está no ar; a rede devolve o asset novo.
    const buildBFetch = vi.fn(async () => new Response('BUILD-B', { status: 200 }))
    const { handlers, cache, store } = loadSw('robotrack-cache-B', buildBFetch)
    // Simula uma cópia velha do build A no cache corrente.
    store.set(`${ORIGIN}/assets/app.js`, new Response('BUILD-A', { status: 200 }))

    let responded: Promise<Response> | undefined
    handlers.fetch({
      request: { url: `${ORIGIN}/assets/app.js`, method: 'GET', mode: 'cors' },
      respondWith: (p: Promise<Response>) => (responded = p),
    })
    const res = await responded!
    expect(await res.text()).toBe('BUILD-B') // com rede, a verdade é a rede
    expect(cache.put).toHaveBeenCalled() // e o build B substitui o A no cache
  })
})
