import { test as base, expect, type BrowserContext, type APIRequestContext } from '@playwright/test'
import { SEED, type SeededUser } from './seed-constants'

// quality-and-accessibility 6.2 (D-QA-1) — a fixture de DUAS sessões simultâneas.
// Os fluxos 1 (convite) e 4 (revogação ao vivo) exigem dono e convidado
// conectados AO MESMO TEMPO, com JWTs DIFERENTES: um só contexto faria os dois
// fluxos passarem pelo motivo errado. Playwright dá isso com dois
// `BrowserContext` no mesmo processo (cookies/localStorage isolados).

// O app chama o backend DIRETO na :3000 (client.ts força a porta) — não pela
// proxy /api do nginx. Então o login E2E bate no backend, como o app faz.
// `E2E_API_URL` sobrepõe (ex.: a origem do backend no compose).
function apiBase(baseURL: string | undefined): string {
  if (process.env.E2E_API_URL) return process.env.E2E_API_URL.replace(/\/$/, '')
  const origin = baseURL ?? 'http://localhost'
  try {
    const u = new URL(origin)
    u.port = '3000'
    return u.origin
  } catch {
    return 'http://localhost:3000'
  }
}

interface Session {
  accessToken: string
  user: { id: string; name?: string; email?: string }
}

// Login pela API pública `POST /auth/v1/session` (root-mounted, não sob /api).
// Devolve o token do corpo `data.access_token` (também vem no header Authorization).
export async function apiLogin(request: APIRequestContext, user: SeededUser, apiUrl: string): Promise<Session> {
  const res = await request.post(`${apiUrl}/auth/v1/session`, {
    data: { email: user.email, password: user.password, remember_me: true },
    headers: { 'Content-Type': 'application/json' },
  })
  if (!res.ok()) {
    throw new Error(
      `[e2e] login falhou para ${user.email}: HTTP ${res.status()}. ` +
        'Rodou `bin/rails rt:seed:e2e[base]` contra este banco?',
    )
  }
  const body = (await res.json()) as { data: Session }
  return body.data
}

// Constrói um BrowserContext JÁ AUTENTICADO injetando a sessão no localStorage no
// formato que o authStore hidrata (`robotrack.session` = {accessToken, user}) — o
// mesmo meio que o app usa, sem clicar na tela de login a cada teste.
export async function authenticatedContext(
  browser: import('@playwright/test').Browser,
  user: SeededUser,
  baseURL: string | undefined,
): Promise<BrowserContext> {
  const apiUrl = apiBase(baseURL)
  const request = await base.request.newContext()
  const session = await apiLogin(request, user, apiUrl)
  await request.dispose()

  const context = await browser.newContext({
    storageState: {
      cookies: [],
      origins: [
        {
          origin: baseURL ?? 'http://localhost',
          localStorage: [
            {
              name: 'robotrack.session',
              value: JSON.stringify({ accessToken: session.accessToken, user: session.user }),
            },
          ],
        },
      ],
    },
  })
  return context
}

// 6.1 — falha IMEDIATA se o service worker não registrar. Contra `vite dev` ou um
// build sem SW, `serviceWorkers()` volta vazio e o fluxo offline mentiria; o teste
// tem que dizer isso, não morrer obscuro dez passos depois.
export async function assertServiceWorkerRegistered(context: BrowserContext): Promise<void> {
  if (context.serviceWorkers().length > 0) return
  await context.waitForEvent('serviceworker', { timeout: 15_000 }).catch(() => {
    throw new Error(
      '[e2e] nenhum service worker registrado — E2E_BASE_URL aponta pro build de ' +
        'produção? Contra `vite dev` o SW de D7 não registra (6.1).',
    )
  })
}

// A fixture: dois contextos autenticados + suas páginas. Cada spec que precise das
// duas sessões declara `ownerPage`/`guestPage`; quem precisa de uma só usa `ownerPage`.
export const test = base.extend<{
  ownerContext: BrowserContext
  guestContext: BrowserContext
  ownerPage: import('@playwright/test').Page
  guestPage: import('@playwright/test').Page
}>({
  ownerContext: async ({ browser, baseURL }, use) => {
    const ctx = await authenticatedContext(browser, SEED.owner, baseURL)
    await use(ctx)
    await ctx.close()
  },
  guestContext: async ({ browser, baseURL }, use) => {
    const ctx = await authenticatedContext(browser, SEED.guest, baseURL)
    await use(ctx)
    await ctx.close()
  },
  ownerPage: async ({ ownerContext }, use) => {
    await use(await ownerContext.newPage())
  },
  guestPage: async ({ guestContext }, use) => {
    await use(await guestContext.newPage())
  },
})

export { expect, SEED }
