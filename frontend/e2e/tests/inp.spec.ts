import { test, expect, SEED } from '../fixtures/session'

// quality-and-accessibility 8.5 (D-QA-6) — INP com EXATAMENTE 24 cards numa célula
// de carga (1440×900, CPU 4×, teto 200 ms p95). Os 24 cards são o cenário que o
// DESIGN.md cita e que ninguém podia reproduzir por falta de dataset — o seed
// `[carga]` o entrega. Requer `rt:seed:e2e[carga]`.
//
// NOTA: a luz ambiente que seguia o mouse (escritas em `--lx`/`--ly`) foi REMOVIDA
// (ver EXECUCAO.md da change design-system). Este arquivo guarda só o gate de INP,
// que independe daquele efeito.
//
// O EntityCard interativo é `role="button"` com `aria-label="Abrir <título>"` (o
// design chama de `.card`; a árvore de a11y é a fonte da verdade). CPU 4× é CDP,
// então o teste de INP é Chromium-only (WebKit não expõe o throttle).

const CELL_PATH = `/projeto/${SEED.carga.project.id}/celula/${SEED.carga.cell.id}`

function percentil(xs: number[], p: number): number {
  if (xs.length === 0) return 0
  const s = [...xs].sort((a, b) => a - b)
  return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)]
}

test.describe('8.5 — INP (1440×900)', () => {
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
})
