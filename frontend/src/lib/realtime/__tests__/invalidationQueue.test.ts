import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { InvalidationQueue } from '../invalidationQueue'
import type { QueryClient } from '@tanstack/react-query'

const client = { invalidateQueries: vi.fn() }
const asClient = () => client as unknown as QueryClient

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
})
