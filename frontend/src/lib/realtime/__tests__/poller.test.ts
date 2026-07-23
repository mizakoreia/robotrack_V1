import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import type { QueryClient } from '@tanstack/react-query'
import { DegradedPoller } from '../poller'
import type { TransportState } from '../../../store/realtimeStore'

describe('DegradedPoller (7.2 / D6.6)', () => {
  let refetchQueries: ReturnType<typeof vi.fn>
  let client: QueryClient
  let transport: TransportState
  let visible: boolean
  let interaction: number
  let clock: number

  beforeEach(() => {
    vi.useFakeTimers()
    refetchQueries = vi.fn()
    client = { refetchQueries } as unknown as QueryClient
    transport = 'degraded'
    visible = true
    interaction = 0
    clock = 0
  })
  afterEach(() => vi.useRealTimers())

  function poller() {
    return new DegradedPoller({
      client,
      getTransport: () => transport,
      subscribe: () => () => {},
      isVisible: () => visible,
      lastInteraction: () => interaction,
      now: () => clock,
      activeMs: 20_000,
      idleMs: 60_000,
      idleAfterMs: 300_000,
    })
  }

  it('em degraded, refetcha as ativas a cada 20s', () => {
    const p = poller()
    p.start()
    vi.advanceTimersByTime(20_000)
    expect(refetchQueries).toHaveBeenCalledWith({ type: 'active' })
    expect(refetchQueries).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(20_000)
    expect(refetchQueries).toHaveBeenCalledTimes(2)
    p.stop()
  })

  it('aba oculta não pesquisa', () => {
    visible = false
    const p = poller()
    p.start()
    vi.advanceTimersByTime(60_000)
    expect(refetchQueries).not.toHaveBeenCalled()
    p.stop()
  })

  it('ociosidade (>5min sem interação) alonga o intervalo para 60s', () => {
    clock = 400_000 // agora
    interaction = 0 // última interação há muito
    const p = poller()
    p.start()
    vi.advanceTimersByTime(20_000)
    expect(refetchQueries).not.toHaveBeenCalled() // 20s não basta no modo ocioso
    vi.advanceTimersByTime(40_000) // total 60s
    expect(refetchQueries).toHaveBeenCalledTimes(1)
    p.stop()
  })

  it('fora de degraded (live) não pesquisa', () => {
    transport = 'live'
    const p = poller()
    p.start()
    vi.advanceTimersByTime(60_000)
    expect(refetchQueries).not.toHaveBeenCalled()
    p.stop()
  })
})
