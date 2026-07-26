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

self.addEventListener('install', (event) => {
  // Precache do shell + assets do build, feito no install (ainda ONLINE). SEM isto
  // o SW só guardava o que passasse por ele DEPOIS de assumir o controle — e o
  // fluxo real (login → Visão Geral por navegação de cliente, sem reload cheio)
  // nunca faz o documento nem os bundles com hash passarem pelo SW. Resultado: o
  // primeiro reload em modo avião falhava com ERR_FAILED (documento fora do cache)
  // e o app NEM BOOTAVA — o usuário já logado ficava preso sem sair. Buscar o
  // index aqui e cachear os assets que ele referencia faz o shell abrir offline; o
  // ProtectedRoute (tolerante a rede ausente) então deixa entrar com a sessão local.
  event.waitUntil(precacheShell())
  // A nova versão assume imediatamente; o usuário é avisado pelo controllerchange.
  self.skipWaiting()
})

// Lê o index servido pelo build e cacheia ele + os assets same-origin (js/css/
// fontes) que ele referencia. Idempotente por deploy: cada build muda o CACHE_NAME
// injetado, então o install roda de novo e reescreve num cache novo (o `activate`
// apaga o antigo). Se estiver offline no install (raro), falha em silêncio — o SW
// segue progressivo e cacheia sob demanda pela rota network-first.
async function precacheShell() {
  try {
    const cache = await caches.open(CACHE_NAME)
    const res = await fetch('/index.html', { cache: 'reload' })
    if (!res || !res.ok) return
    // O shell é gravado sob '/index.html' — a MESMA chave que o fallback de
    // navegação (`networkFirst`) procura para servir qualquer rota offline.
    await cache.put('/index.html', res.clone())
    const html = await res.text()
    const assets = new Set()
    // Só caminhos same-origin (começam com '/'): o preconnect/stylesheet do Google
    // Fonts é cross-origin e fica de fora (degrada para a fallback stack offline).
    for (const m of html.matchAll(/(?:src|href)="(\/[^"?]+\.(?:js|css|woff2?))/g)) {
      assets.add(m[1])
    }
    await Promise.all([...assets].map((u) => cache.add(u).catch(() => {})))
  } catch {
    /* offline no install: nada a pré-cachear; o SW segue progressivo */
  }
}

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
//
// `ignoreVary: true` nas leituras é ESSENCIAL: os assets do build são servidos
// com `Vary: Origin`, e os JS/CSS de módulo carregam com `crossorigin` (modo
// `cors`, que manda header `Origin`). O precache do install grava via `cache.add`,
// cujo request interno tem outro `Origin` — então um `match` que respeita o Vary
// ERRA a cópia e o app abre offline SEM os bundles (shell em branco). Ignorar o
// Vary casa a URL e devolve o asset gravado. (Era por isso que só a rota já
// visitada online abria offline: ali a cópia foi gravada pelo próprio request cors.)
async function networkFirst(req) {
  const cache = await caches.open(CACHE_NAME)
  try {
    const res = await fetch(req)
    if (res && res.ok) cache.put(req, res.clone())
    return res
  } catch (err) {
    const cached = await cache.match(req, { ignoreVary: true })
    if (cached) return cached
    // Navegação offline sem cópia da própria URL → devolve o shell da SPA, que
    // roteia no cliente (`/projetos/P/celulas/C/robos/R` offline responde 200).
    if (req.mode === 'navigate') {
      const shell = await cache.match('/index.html', { ignoreVary: true })
      if (shell) return shell
    }
    throw err
  }
}
