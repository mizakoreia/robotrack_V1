import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { InvalidationQueue } from '../invalidationQueue'
import type { InvalidationGate } from '../invalidationGate'
import type { QueryClient } from '@tanstack/react-query'
import type { QueryKey } from '../eventMap'

const client = { invalidateQueries: vi.fn() }
const asClient = () => client as unknown as QueryClient

// Gate controlável: `dammed` guarda as chaves (serializadas) represadas agora;
// `settle()` simula uma mutação assentando (dispara o re-dreno do represado).
function fakeGate() {
  const dammed = new Set<string>()
  let cb: () => void = () => {}
  const gate = {
    isDammed: (k: QueryKey) => dammed.has(JSON.stringify(k)),
    subscribeSettle: (fn: () => void) => {
      cb = fn
      return () => {}
    },
  } as unknown as InvalidationGate
  return { gate, dammed, settle: () => cb() }
}

describe('InvalidationQueue (5.4 / D6.2)', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    client.invalidateQueries.mockClear()
  })
  afterEach(() => vi.useRealTimers())

  it('rajada da MESMA chave em 250ms vira UM refetch, com refetchType active', () => {
    const q = new InvalidationQueue(asClient(), 250)
    for (let i = 0; i < 8; i++) q.enqueue([['ws', 'w', 'robot', 'r']])
    expect(client.invalidateQueries).not.toHaveBeenCalled() // ainda represado
    vi.advanceTimersByTime(250)
    expect(client.invalidateQueries).toHaveBeenCalledTimes(1)
    expect(client.invalidateQueries).toHaveBeenCalledWith({ queryKey: ['ws', 'w', 'robot', 'r'], refetchType: 'active' })
  })

  it('chaves distintas são invalidadas uma vez cada', () => {
    const q = new InvalidationQueue(asClient(), 250)
    q.enqueue([['ws', 'w', 'overview'], ['ws', 'w', 'my-tasks']])
    q.enqueue([['ws', 'w', 'overview']]) // dup
    vi.advanceTimersByTime(250)
    expect(client.invalidateQueries).toHaveBeenCalledTimes(2)
  })

  it('clear() descarta o represado sem invalidar', () => {
    const q = new InvalidationQueue(asClient(), 250)
    q.enqueue([['ws', 'w', 'overview']])
    q.clear()
    vi.advanceTimersByTime(500)
    expect(client.invalidateQueries).not.toHaveBeenCalled()
    expect(q.size).toBe(0)
  })

  it('represa chave colidindo com mutação em voo; drena quando a mutação assenta', () => {
    const { gate, dammed, settle } = fakeGate()
    const onFullyDrained = vi.fn()
    const key = ['ws', 'w', 'robot', 'r']
    dammed.add(JSON.stringify(key))
    const q = new InvalidationQueue(asClient(), { intervalMs: 250, gate, onFullyDrained })

    q.enqueue([key])
    vi.advanceTimersByTime(250) // dreno → represado, NÃO invalida
    expect(client.invalidateQueries).not.toHaveBeenCalled()
    expect(q.deferredSize).toBe(1)

    dammed.clear()
    settle() // mutação assentou (sucesso OU erro) → re-dreno
    expect(client.invalidateQueries).toHaveBeenCalledWith({ queryKey: key, refetchType: 'active' })
    expect(onFullyDrained).toHaveBeenCalled()
    expect(q.deferredSize).toBe(0)
  })

  it('teto de 30s: represada além disso invalida assim mesmo e marca não-sincronizado', () => {
    const { gate, dammed } = fakeGate()
    const onCeilingBreach = vi.fn()
    const key = ['ws', 'w', 'robot', 'r']
    dammed.add(JSON.stringify(key)) // fica represada o tempo todo
    const q = new InvalidationQueue(asClient(), { intervalMs: 250, gate, ceilingMs: 30_000, onCeilingBreach })

    q.enqueue([key])
    vi.advanceTimersByTime(250) // represa
    expect(client.invalidateQueries).not.toHaveBeenCalled()

    vi.advanceTimersByTime(30_000) // estoura o teto (Date.now avança com os fake timers)
    expect(client.invalidateQueries).toHaveBeenCalledWith({ queryKey: key, refetchType: 'active' })
    expect(onCeilingBreach).toHaveBeenCalled()
    expect(q.deferredSize).toBe(0)
  })
})
