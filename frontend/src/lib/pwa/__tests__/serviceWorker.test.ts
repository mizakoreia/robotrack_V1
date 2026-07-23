import { describe, it, expect, beforeEach, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

// offline-pwa 2.5 — a suíte roda contra o PRÓPRIO public/sw.js (lido do disco e
// avaliado num sandbox), não contra uma cópia. Se alguém adicionar uma rota de
// cache de API, o caso `/api/v1/robots` quebra. Os globais de worker (`self`,
// `caches`, `fetch`) são injetados como parâmetros.

const ORIGIN = 'https://app.robotrack.test'
const SW_SOURCE = readFileSync(resolve(__dirname, '../../../../public/sw.js'), 'utf8')

class FakeCache {
  store = new Map<string, Response>()
  put = vi.fn(async (req: { url: string }, res: Response) => {
    this.store.set(req.url, res)
  })
  match = vi.fn(async (req: { url: string } | string) => {
    const url = typeof req === 'string' ? req : req.url
    return this.store.get(url) ?? this.store.get(new URL(url, ORIGIN).pathname)
  })
}

class FakeCaches {
  map = new Map<string, FakeCache>()
  open = vi.fn(async (name: string) => {
    let c = this.map.get(name)
    if (!c) {
      c = new FakeCache()
      this.map.set(name, c)
    }
    return c
  })
  keys = vi.fn(async () => [...this.map.keys()])
  delete = vi.fn(async (name: string) => this.map.delete(name))
}

type Handler = (event: unknown) => void

function loadSw(fetchImpl: typeof fetch) {
  const handlers: Record<string, Handler> = {}
  const self = {
    location: { origin: ORIGIN },
    addEventListener: (type: string, h: Handler) => {
      handlers[type] = h
    },
    skipWaiting: vi.fn(),
    clients: { claim: vi.fn(async () => {}) },
  }
  const caches = new FakeCaches()
  new Function('self', 'caches', 'fetch', SW_SOURCE)(self, caches, fetchImpl)
  return { handlers, self, caches }
}

function req(url: string, init: { method?: string; mode?: string } = {}) {
  return { url: new URL(url, ORIGIN).toString(), method: init.method ?? 'GET', mode: init.mode }
}

function fetchEvent(request: ReturnType<typeof req>) {
  let responded: Promise<Response> | undefined
  const event = {
    request,
    respondWith: vi.fn((p: Promise<Response>) => {
      responded = p
    }),
  }
  return { event, get responded() { return responded } }
}

describe('service worker — guarda de não-interceptação (2.2)', () => {
  const okFetch = vi.fn(async () => new Response('ok', { status: 200 }))

  const bypass: Array<[string, ReturnType<typeof req>]> = [
    ['GET /api/v1/robots (backend)', req('/api/v1/robots')],
    ['GET /auth/callback (backend)', req('/auth/callback')],
    ['GET /cable (WebSocket upgrade)', req('/cable')],
    ['GET /rails/active_storage/blob (backend)', req('/rails/active_storage/blobs/x')],
    ['POST same-origin (não-GET)', req('/projetos', { method: 'POST' })],
    ['GET cross-origin', { url: 'https://cdn.outra.com/x.js', method: 'GET', mode: undefined }],
  ]

  for (const [nome, request] of bypass) {
    it(`${nome} → NÃO chama respondWith`, () => {
      const { handlers } = loadSw(okFetch)
      const { event } = fetchEvent(request as ReturnType<typeof req>)
      handlers.fetch(event)
      expect(event.respondWith).not.toHaveBeenCalled()
    })
  }
})

describe('service worker — network-first same-origin (2.3)', () => {
  it('asset GET ok → respondWith, cacheia a resposta e devolve a da rede', async () => {
    const netFetch = vi.fn(async () => new Response('js', { status: 200 }))
    const { handlers, caches } = loadSw(netFetch)
    const { event, } = fetchEvent(req('/assets/app.js'))
    handlers.fetch(event)
    const res = await event.respondWith.mock.calls[0][0]
    expect(res.status).toBe(200)
    const cache = await caches.open('__CACHE_NAME__')
    expect(cache.put).toHaveBeenCalled()
  })

  it('resposta 503 NÃO sobrescreve o cache (só `ok` é gravado)', async () => {
    const netFetch = vi.fn(async () => new Response('down', { status: 503 }))
    const { handlers, caches } = loadSw(netFetch)
    const { event } = fetchEvent(req('/assets/app.js'))
    handlers.fetch(event)
    const res = await event.respondWith.mock.calls[0][0]
    expect(res.status).toBe(503)
    const cache = await caches.open('__CACHE_NAME__')
    expect(cache.put).not.toHaveBeenCalled()
  })

  it('offline (fetch lança) → devolve a cópia em cache', async () => {
    const netFetch = vi.fn(async () => {
      throw new Error('offline')
    })
    const { handlers, caches } = loadSw(netFetch)
    const cache = await caches.open('__CACHE_NAME__')
    cache.store.set(new URL('/assets/app.js', ORIGIN).toString(), new Response('cache', { status: 200 }))
    const { event } = fetchEvent(req('/assets/app.js'))
    handlers.fetch(event)
    const res = await event.respondWith.mock.calls[0][0]
    expect(await res.text()).toBe('cache')
  })

  it('navegação offline sem cópia da URL → devolve o shell /index.html (200)', async () => {
    const netFetch = vi.fn(async () => {
      throw new Error('offline')
    })
    const { handlers, caches } = loadSw(netFetch)
    const cache = await caches.open('__CACHE_NAME__')
    cache.store.set('/index.html', new Response('<html>shell</html>', { status: 200 }))
    const { event } = fetchEvent(req('/projetos/P/celulas/C/robos/R', { mode: 'navigate' }))
    handlers.fetch(event)
    const res = await event.respondWith.mock.calls[0][0]
    expect(res.status).toBe(200)
    expect(await res.text()).toContain('shell')
  })
})

describe('service worker — activate purga caches antigos (2.1)', () => {
  it('apaga o cache anterior e o legado robotrack-v9-, mantém o corrente, e faz claim', async () => {
    const { handlers, self, caches } = loadSw(vi.fn())
    caches.map.set('robotrack-cache-antigo', new FakeCache())
    caches.map.set('robotrack-v9-cache-v25', new FakeCache())
    caches.map.set('__CACHE_NAME__', new FakeCache()) // o corrente (placeholder no teste)
    caches.map.set('outro-app-cache', new FakeCache()) // de outro app, não tocar

    let done: Promise<unknown> = Promise.resolve()
    handlers.activate({ waitUntil: (p: Promise<unknown>) => (done = p) })
    await done

    expect(caches.map.has('robotrack-cache-antigo')).toBe(false)
    expect(caches.map.has('robotrack-v9-cache-v25')).toBe(false)
    expect(caches.map.has('__CACHE_NAME__')).toBe(true)
    expect(caches.map.has('outro-app-cache')).toBe(true)
    expect(self.clients.claim).toHaveBeenCalled()
  })
})

describe('service worker — install (2.1)', () => {
  it('chama skipWaiting', () => {
    const { handlers, self } = loadSw(vi.fn())
    handlers.install({})
    expect(self.skipWaiting).toHaveBeenCalled()
  })
})
