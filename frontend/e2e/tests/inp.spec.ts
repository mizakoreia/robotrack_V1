import { test, expect, SEED } from '../fixtures/session'

// quality-and-accessibility 8.5 (§Luz ambiente / D-QA-6) — INP com EXATAMENTE 24
// cards numa célula de carga (1440×900, CPU 4×, teto 200 ms p95) MAIS a cadência da
// luz ambiente: ≤100 escritas em `--lx`/`--ly` em 3 s, e ZERO num viewport de toque.
// Os 24 cards são o cenário que o DESIGN.md cita e que ninguém podia reproduzir por
// falta de dataset — o seed `[carga]` o entrega. Requer `rt:seed:e2e[carga]`.
//
// NOTA: o EntityCard interativo é `role="button"` com `aria-label="Abrir <título>"`
// (o design chama de `.card`; a árvore de a11y é a fonte da verdade). CPU 4× é CDP,
// então o teste de INP é Chromium-only (WebKit não expõe o throttle).

const CELL_PATH = `/projeto/${SEED.carga.project.id}/celula/${SEED.carga.cell.id}`

function percentil(xs: number[], p: number): number {
  if (xs.length === 0) return 0
  const s = [...xs].sort((a, b) => a - b)
  return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)]
}

test.describe('8.5 — INP e cadência da luz ambiente (1440×900)', () => {
  test.use({ viewport: { width: 1440, height: 900 } })

  test('24 cards: INP p95 < 200ms sob CPU 4×', async ({ ownerPage, browserName }) => {
    test.skip(browserName !== 'chromium', 'CPU throttling é via CDP (Chromium-only)')
    await ownerPage.goto(CELL_PATH)
    // 24 cards em tela — o cenário do DESIGN.md.
    const cards = ownerPage.getByRole('button', { name: /^Abrir / })
    await expect(cards).toHaveCount(SEED.carga.robotCount)

    // CPU 4× (CDP) — o chão de fábrica não roda num laptop de dev.
    const cdp = await ownerPage.context().newCDPSession(ownerPage)
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 })

    // Instrumenta o Event Timing: coleta a duração de cada interação.
    await ownerPage.evaluate(() => {
      ;(window as unknown as { __inp: number[] }).__inp = []
      const po = new PerformanceObserver((list) => {
        for (const e of list.getEntries()) (window as unknown as { __inp: number[] }).__inp.push(e.duration)
      })
      po.observe({ type: 'event', durationThreshold: 0, buffered: true } as PerformanceObserverInit)
    })

    // 24 interações de teclado (keydown/up entram no Event Timing sem navegar).
    for (let i = 0; i < SEED.carga.robotCount; i++) await ownerPage.keyboard.press('Tab')

    const durations = await ownerPage.evaluate(() => (window as unknown as { __inp: number[] }).__inp)
    expect(durations.length).toBeGreaterThan(0) // capturou interações de verdade
    expect(percentil(durations, 95)).toBeLessThan(200)
  })

  test('a luz ambiente escreve ≤100× em --lx/--ly em 3s (com ponteiro fino)', async ({ ownerPage }) => {
    await ownerPage.goto(CELL_PATH)
    await expect(ownerPage.getByRole('button', { name: /^Abrir / })).toHaveCount(SEED.carga.robotCount)

    // Conta as escritas em --lx/--ly enquanto o ponteiro se move por ~3s. rAF (não
    // setTimeout — o e2e:lint proíbe espera-por-tempo) dirige o laço até 3000ms.
    const writes = await ownerPage.evaluate(
      () =>
        new Promise<number>((resolve) => {
          const root = document.documentElement
          const orig = root.style.setProperty.bind(root.style)
          let count = 0
          root.style.setProperty = (prop: string, val: string | null, prio?: string) => {
            if (prop === '--lx' || prop === '--ly') count++
            return orig(prop, val, prio)
          }
          const start = performance.now()
          let x = 0
          const frame = () => {
            x = (x + 17) % 1400
            window.dispatchEvent(new PointerEvent('pointermove', { clientX: x, clientY: x % 800, bubbles: true }))
            if (performance.now() - start < 3000) requestAnimationFrame(frame)
            else {
              root.style.setProperty = orig
              resolve(count)
            }
          }
          requestAnimationFrame(frame)
        }),
    )
    // O throttle de 32ms cabe ~93 escritas em 3s: registra a luz, mas NÃO invalida
    // toda superfície de vidro a cada mousemove.
    expect(writes).toBeGreaterThan(0)
    expect(writes).toBeLessThanOrEqual(100)
  })
})

// Viewport de TOQUE: a luz ambiente é gated por `(hover:hover) and (pointer:fine)` —
// num aparelho de toque o listener NEM se registra, então ZERO escritas.
test.describe('8.5 — luz ambiente NÃO roda no toque', () => {
  test.use({ viewport: { width: 375, height: 812 }, hasTouch: true, isMobile: true })

  test('zero escritas em --lx/--ly num viewport de toque', async ({ ownerPage }) => {
    await ownerPage.goto(CELL_PATH)
    await expect(ownerPage.getByRole('button', { name: /^Abrir / }).first()).toBeVisible()

    const writes = await ownerPage.evaluate(
      () =>
        new Promise<number>((resolve) => {
          const root = document.documentElement
          const orig = root.style.setProperty.bind(root.style)
          let count = 0
          root.style.setProperty = (prop: string, val: string | null, prio?: string) => {
            if (prop === '--lx' || prop === '--ly') count++
            return orig(prop, val, prio)
          }
          const start = performance.now()
          const frame = () => {
            window.dispatchEvent(new PointerEvent('pointermove', { clientX: 100, clientY: 100, bubbles: true }))
            if (performance.now() - start < 1000) requestAnimationFrame(frame)
            else {
              root.style.setProperty = orig
              resolve(count)
            }
          }
          requestAnimationFrame(frame)
        }),
    )
    expect(writes).toBe(0)
  })
})
