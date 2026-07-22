import { afterEach, describe, expect, it, vi } from 'vitest'
import { initAmbient } from '../src/lib/ambient'

// design-system 7.1/7.3 (D-DS-6) — a luz escreve no máximo ~32 vezes em 1000ms
// (throttle 32ms), NÃO registra listener no toque, e CONGELA sob movimento
// reduzido.

function fakeWin(mediaMatches: (q: string) => boolean) {
  const listeners: Record<string, (e: unknown) => void> = {}
  return {
    matchMedia: (q: string) => ({ matches: mediaMatches(q) }),
    addEventListener: (t: string, fn: (e: unknown) => void) => {
      listeners[t] = fn
    },
    removeEventListener: (t: string) => {
      delete listeners[t]
    },
    _emit: (t: string, e: unknown) => listeners[t]?.(e),
    _has: (t: string) => Boolean(listeners[t]),
  }
}

afterEach(() => vi.restoreAllMocks())

describe('luz ambiente (D-DS-6)', () => {
  it('60 pointermove em 1000ms produzem no máximo 32 escritas (throttle 32ms)', () => {
    const root = document.createElement('div')
    const setProp = vi.spyOn(root.style, 'setProperty')
    let t = 0
    vi.spyOn(performance, 'now').mockImplementation(() => t)

    const win = fakeWin((q) => q.includes('hover'))
    initAmbient(root, win as unknown as Window)

    // 60 eventos ao longo de 1000ms (≈16.6ms cada — 60fps)
    for (let i = 0; i < 60; i++) {
      t = (i * 1000) / 60
      win._emit('pointermove', { clientX: i, clientY: i })
    }
    // setProperty é chamado 2×/escrita (--lx e --ly)
    const writes = setProp.mock.calls.filter((c) => c[0] === '--lx').length
    expect(writes).toBeLessThanOrEqual(32)
    expect(writes).toBeGreaterThan(20) // e não é zero — a luz de fato segue
  })

  it('no toque (sem hover fino) não registra listener nenhum', () => {
    const win = fakeWin(() => false)
    initAmbient(document.createElement('div'), win as unknown as Window)
    expect(win._has('pointermove')).toBe(false)
  })

  it('sob movimento reduzido, congela: não registra listener', () => {
    const win = fakeWin((q) => q.includes('hover') || q.includes('reduced'))
    initAmbient(document.createElement('div'), win as unknown as Window)
    expect(win._has('pointermove')).toBe(false)
  })
})
