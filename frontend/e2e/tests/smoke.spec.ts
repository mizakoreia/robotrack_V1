import { test, expect, SEED } from '../fixtures/session'
import { assertServiceWorkerRegistered } from '../fixtures/session'

// quality-and-accessibility 6.3 — smoke do HARNESS (não de um fluxo). Prova, em
// Chromium E WebKit, que a espinha dorsal está de pé: o build de produção carrega,
// o service worker de D7 REGISTRA (6.1), e uma sessão semeada (rt:seed:e2e[base])
// entra AUTENTICADA sem clicar no login. Se ISTO falha, nenhum dos 5 fluxos vale.
//
// As asserções afirmam AUTENTICAÇÃO DE VERDADE: só `#root` visível e o `user` no
// localStorage passavam TAMBÉM na tela de login (o BUG 15 deixava o token cair, e o
// smoke "passava" por acaso). Agora exigimos (a) o token no storage e (b) o shell
// autenticado (destino "Visão Geral" da sidebar, que NÃO existe na tela de login) e
// (c) ausência do heading "Entrar".
test.describe('harness E2E — smoke', () => {
  test('a sessão semeada entra AUTENTICADA e o service worker registra', async ({ ownerPage }) => {
    await ownerPage.goto('/')

    // (a) o token está no storage (não só o user) — o que o BUG 15 quebrava.
    const session = await ownerPage.evaluate(() => localStorage.getItem('robotrack.session'))
    expect(session).toContain('accessToken')

    // (b) o shell AUTENTICADO renderizou: o destino "Visão Geral" só existe no AppShell.
    await expect(ownerPage.getByRole('link', { name: /Visão Geral/ })).toBeVisible()
    // (c) e não estamos na tela de login.
    await expect(ownerPage.getByRole('heading', { name: 'Entrar' })).toHaveCount(0)

    // Service worker de D7 (afirmado pela página — cross-browser, BUG 14).
    await assertServiceWorkerRegistered(ownerPage)
  })

  test('as duas sessões têm identidades DISTINTAS e ambas com token', async ({ ownerPage, guestPage }) => {
    await ownerPage.goto('/')
    await guestPage.goto('/')
    const ownerSession = await ownerPage.evaluate(() => localStorage.getItem('robotrack.session'))
    const guestSession = await guestPage.evaluate(() => localStorage.getItem('robotrack.session'))
    // cada um autenticado (token presente) e com identidade própria
    expect(ownerSession).toContain('accessToken')
    expect(guestSession).toContain('accessToken')
    expect(ownerSession).toContain(SEED.owner.id)
    expect(guestSession).toContain(SEED.guest.id)
    expect(ownerSession).not.toEqual(guestSession)
  })
})
