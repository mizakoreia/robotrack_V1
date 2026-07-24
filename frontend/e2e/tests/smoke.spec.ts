import { test, expect, SEED } from '../fixtures/session'
import { assertServiceWorkerRegistered } from '../fixtures/session'

// quality-and-accessibility 6.3 — smoke do HARNESS (não de um fluxo). Prova, em
// Chromium E WebKit, que a espinha dorsal está de pé: o build de produção carrega,
// o service worker de D7 REGISTRA (6.1), e uma sessão semeada (rt:seed:e2e[base])
// entra autenticada sem clicar no login. Se ISTO falha, nenhum dos 5 fluxos vale.
test.describe('harness E2E — smoke', () => {
  test('o build de produção carrega e registra o service worker', async ({ ownerPage }) => {
    await ownerPage.goto('/')
    // O shell autenticado renderiza (não a tela de login) — a sessão semeada valeu.
    await expect(ownerPage.locator('#root')).toBeVisible()
    // Afirma pela página (cross-browser), não por ctx.serviceWorkers() (BUG 14).
    await assertServiceWorkerRegistered(ownerPage)
  })

  test('as duas sessões têm identidades DISTINTAS (contextos isolados)', async ({ ownerPage, guestPage }) => {
    // Cada contexto hidrata sua própria sessão do localStorage; provamos que os
    // tokens/usuários não vazam entre eles (base dos fluxos 1 e 4).
    await ownerPage.goto('/')
    await guestPage.goto('/')
    const ownerSession = await ownerPage.evaluate(() => localStorage.getItem('robotrack.session'))
    const guestSession = await guestPage.evaluate(() => localStorage.getItem('robotrack.session'))
    expect(ownerSession).toContain(SEED.owner.id)
    expect(guestSession).toContain(SEED.guest.id)
    expect(ownerSession).not.toEqual(guestSession)
  })
})
