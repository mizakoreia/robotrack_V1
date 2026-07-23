import { describe, it, expect, vi } from 'vitest'
import { sentryConfig, initClientSentry } from '../sentry'

// delivery-and-observability 4.2 — a lógica de config do Sentry cliente.

describe('sentryConfig (4.2)', () => {
  it('sem DSN → null (desligado)', () => {
    expect(sentryConfig({ MODE: 'production' })).toBeNull()
  })

  it('em teste → null mesmo com DSN', () => {
    expect(sentryConfig({ VITE_SENTRY_DSN: 'https://x@sentry/1', MODE: 'test' })).toBeNull()
  })

  it('com DSN → release atrelada ao hash do build e environment', () => {
    const cfg = sentryConfig({
      VITE_SENTRY_DSN: 'https://x@sentry/1',
      VITE_SENTRY_RELEASE: 'abc123',
      MODE: 'production',
    })
    expect(cfg).toEqual({ dsn: 'https://x@sentry/1', release: 'abc123', environment: 'production' })
  })
})

describe('initClientSentry (4.2)', () => {
  it('chama o init injetado quando há DSN', () => {
    const init = vi.fn()
    const ran = initClientSentry(init, { VITE_SENTRY_DSN: 'https://x@sentry/1', MODE: 'production' })
    expect(ran).toBe(true)
    expect(init).toHaveBeenCalledWith(expect.objectContaining({ dsn: 'https://x@sentry/1' }))
  })

  it('no-op sem DSN', () => {
    const init = vi.fn()
    expect(initClientSentry(init, { MODE: 'production' })).toBe(false)
    expect(init).not.toHaveBeenCalled()
  })

  it('no-op sem init injetado', () => {
    expect(initClientSentry(undefined, { VITE_SENTRY_DSN: 'https://x@sentry/1', MODE: 'production' })).toBe(false)
  })
})
