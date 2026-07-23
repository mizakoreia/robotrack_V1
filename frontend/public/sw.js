/* RoboTrack — service worker (offline-pwa 2.1-2.4 / D7-1..D7-3).
 *
 * Este arquivo é a ÚNICA fonte de verdade do worker: a suíte de 2.5 carrega este
 * próprio código-fonte e dispara FetchEvents sintéticos contra ele (sem cópia,
 * sem drift). `self`, `caches`, `fetch` e `clients` são os globais do escopo de
 * worker — no teste são injetados como parâmetros de um sandbox.
 *
 * Guarda de NÃO-interceptação (D7-1): o SW só toca GET same-origin que NÃO seja
 * rota de backend. Backend (`/api|/auth|/cable|/rails/active_storage`), qualquer
 * não-GET e cross-origin passam pelo comportamento NATIVO do browser — não
 * chamamos `respondWith`. É o que preserva streaming, `Authorization` e o upgrade
 * de WebSocket do `/cable`. Herdar a checagem de origem do SW legado interceptaria
 * `/api` no dia em que a topologia virasse same-origin.
 *
 * CACHE_NAME é injetado no build pelo plugin do Vite (2.4): o placeholder abaixo
 * vira `robotrack-cache-<hash-do-build>`, de modo que cada deploy ativa um cache
 * novo e o `activate` apaga o anterior.
 */
const CACHE_NAME = '__CACHE_NAME__'
const CACHE_PREFIX = 'robotrack-cache-'
const LEGACY_PREFIX = 'robotrack-v9-' // PWA Firebase antigo (robotrack-v9-cache-v25)
// `(\/|$)` fecha no fim de segmento OU no fim do caminho: `/cable` (handshake do
// WebSocket, sem barra final) casa tanto quanto `/api/v1/robots`.
const BYPASS_PATH = /^\/(api|auth|cable|rails\/active_storage)(\/|$)/

self.addEventListener('install', () => {
  // A nova versão assume imediatamente; o usuário é avisado pelo controllerchange.
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys()
      await Promise.all(
        keys
          .filter((k) => k !== CACHE_NAME && (k.startsWith(CACHE_PREFIX) || k.startsWith(LEGACY_PREFIX)))
          .map((k) => caches.delete(k)),
      )
      await self.clients.claim()
    })(),
  )
})

self.addEventListener('fetch', (event) => {
  const req = event.request
  const url = new URL(req.url)

  if (req.method !== 'GET' || url.origin !== self.location.origin || BYPASS_PATH.test(url.pathname)) {
    return // sem respondWith → o browser trata nativamente
  }

  event.respondWith(networkFirst(req))
})

// Network-first same-origin: a rede manda; o cache é rede de segurança offline.
// Só respostas `ok` entram no cache — um 503 NÃO sobrescreve uma cópia válida.
async function networkFirst(req) {
  const cache = await caches.open(CACHE_NAME)
  try {
    const res = await fetch(req)
    if (res && res.ok) cache.put(req, res.clone())
    return res
  } catch (err) {
    const cached = await cache.match(req)
    if (cached) return cached
    // Navegação offline sem cópia da própria URL → devolve o shell da SPA, que
    // roteia no cliente (`/projetos/P/celulas/C/robos/R` offline responde 200).
    if (req.mode === 'navigate') {
      const shell = await cache.match('/index.html')
      if (shell) return shell
    }
    throw err
  }
}
