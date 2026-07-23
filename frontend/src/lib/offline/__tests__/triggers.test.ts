import { describe, it, expect, vi } from 'vitest'
import { installDrainTriggers } from '../triggers'
import { probeHealth } from '../health'

// offline-pwa 4.3 — os gatilhos e a sonda de saúde.

function fakeTarget() {
  const listeners: Record<string, Set<() => void>> = {}
  return {
    addEventListener: (t: string, cb: () => void) => {
      ;(listeners[t] ??= new Set()).add(cb)
    },
    removeEventListener: (t: string, cb: () => void) => {
      listeners[t]?.delete(cb)
    },
    fire: (t: string) => listeners[t]?.forEach((cb) => cb()),
    count: (t: string) => listeners[t]?.size ?? 0,
  }
}

describe('installDrainTriggers (4.3)', () => {
  it('online, focus, visibilitychange (visível) e o timer disparam o run', () => {
    const run = vi.fn()
    const win = fakeTarget()
    const doc = { ...fakeTarget(), visibilityState: 'visible' as DocumentVisibilityState }
    let timerCb: () => void = () => {}
    const setIntervalFn = vi.fn((cb: () => void) => {
      timerCb = cb
      return 1
    })
    const clearIntervalFn = vi.fn()

    const stop = installDrainTriggers({ run, win, doc, setInterval: setIntervalFn, clearInterval: clearIntervalFn })

    win.fire('online')
    win.fire('focus')
    doc.fire('visibilitychange')
    timerCb()
    expect(run).toHaveBeenCalledTimes(4)

    stop()
    expect(win.count('online')).toBe(0)
    expect(clearIntervalFn).toHaveBeenCalledWith(1)
  })

  it('visibilitychange oculto NÃO dispara', () => {
    const run = vi.fn()
    const win = fakeTarget()
    const doc = { ...fakeTarget(), visibilityState: 'hidden' as DocumentVisibilityState }
    installDrainTriggers({ run, win, doc, setInterval: () => 1, clearInterval: () => {} })
    doc.fire('visibilitychange')
    expect(run).not.toHaveBeenCalled()
  })
})

describe('probeHealth (4.3)', () => {
  it('HEAD ok → true', async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 200 }))
    expect(await probeHealth({ fetchImpl, baseUrl: 'http://x' })).toBe(true)
    expect(fetchImpl).toHaveBeenCalledWith('http://x/api/v1/health', expect.objectContaining({ method: 'HEAD' }))
  })

  it('status não-ok → false', async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 503 }))
    expect(await probeHealth({ fetchImpl, baseUrl: 'http://x' })).toBe(false)
  })

  it('erro de rede (sem rota de saída) → false, sem lançar', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error('network')
    })
    expect(await probeHealth({ fetchImpl, baseUrl: 'http://x' })).toBe(false)
  })
})
