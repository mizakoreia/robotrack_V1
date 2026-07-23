import { describe, it, expect, beforeEach, vi } from 'vitest'
import { registerServiceWorker, resetServiceWorkerState } from '../register'

const toastMock = vi.fn()
vi.mock('sonner', () => ({ toast: (...args: unknown[]) => toastMock(...args) }))

// offline-pwa 2.4 — o registro é injetável para testar sem um SW real. O que
// importa: só registra em produção; `controllerchange` (deploy assumiu a aba)
// avisa UMA vez e oferece recarregar; a falha de registro não propaga.

function fakeContainer() {
  const listeners: Record<string, () => void> = {}
  return {
    addEventListener: (type: string, cb: () => void) => {
      listeners[type] = cb
    },
    register: vi.fn(async () => ({})),
    fire: (type: string) => listeners[type]?.(),
  } as unknown as ServiceWorkerContainer & { register: ReturnType<typeof vi.fn>; fire: (t: string) => void }
}

describe('registerServiceWorker (2.4)', () => {
  beforeEach(() => {
    toastMock.mockReset()
    resetServiceWorkerState()
  })

  it('não registra fora de produção', () => {
    const c = fakeContainer()
    registerServiceWorker({ swContainer: c, isProd: false, onLoad: (cb) => cb() })
    expect(c.register).not.toHaveBeenCalled()
  })

  it('em produção, registra /sw.js no load', () => {
    const c = fakeContainer()
    registerServiceWorker({ swContainer: c, isProd: true, onLoad: (cb) => cb() })
    expect(c.register).toHaveBeenCalledWith('/sw.js')
  })

  it('controllerchange avisa uma vez e oferece recarregar', () => {
    const c = fakeContainer()
    const reload = vi.fn()
    registerServiceWorker({ swContainer: c, isProd: true, reload, onLoad: () => {} })

    c.fire('controllerchange')
    c.fire('controllerchange') // segunda troca não duplica o aviso

    expect(toastMock).toHaveBeenCalledTimes(1)
    const [, opts] = toastMock.mock.calls[0]
    expect(opts.action.label).toBe('Recarregar')
    opts.action.onClick()
    expect(reload).toHaveBeenCalled()
  })

  it('falha de register não propaga', () => {
    const c = fakeContainer()
    c.register.mockRejectedValueOnce(new Error('sem SW'))
    expect(() => registerServiceWorker({ swContainer: c, isProd: true, onLoad: (cb) => cb() })).not.toThrow()
  })
})
