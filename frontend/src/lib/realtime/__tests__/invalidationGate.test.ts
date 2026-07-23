import { describe, it, expect } from 'vitest'
import type { QueryClient } from '@tanstack/react-query'
import { InvalidationGate, keysIntersect, isPrefix, entityOf, type OfflinePendingProbe } from '../invalidationGate'
import type { QueryKey } from '../eventMap'

function clientWithPending(keys: QueryKey[]): QueryClient {
  return {
    getMutationCache: () => ({
      getAll: () => keys.map((k) => ({ state: { status: 'pending' as const }, options: { mutationKey: k } })),
      subscribe: () => () => {},
    }),
  } as unknown as QueryClient
}

describe('InvalidationGate (6.2/6.3 / D6.4)', () => {
  it('isPrefix / keysIntersect: prefixo em qualquer direção intersecta', () => {
    expect(isPrefix(['ws', 'w', 'robot', 'r'], ['ws', 'w', 'robot', 'r', 'tasks'])).toBe(true)
    expect(keysIntersect(['ws', 'w', 'robot', 'r'], ['ws', 'w', 'robot', 'r', 'tasks'])).toBe(true)
    expect(keysIntersect(['ws', 'w', 'robot', 'r', 'tasks'], ['ws', 'w', 'robot', 'r'])).toBe(true)
    expect(keysIntersect(['ws', 'w', 'robot', 'r'], ['ws', 'w', 'robot', 'r2'])).toBe(false)
    expect(keysIntersect(['ws', 'w', 'robot', 'r'], ['ws', 'w', 'overview'])).toBe(false)
  })

  it('entityOf extrai {kind,id} só de chaves de entidade', () => {
    expect(entityOf(['ws', 'w', 'robot', 'r'])).toEqual({ kind: 'robot', id: 'r' })
    expect(entityOf(['ws', 'w', 'project', 'p', 'cells'])).toEqual({ kind: 'project', id: 'p' })
    expect(entityOf(['ws', 'w', 'overview'])).toBeNull()
    expect(entityOf(['ws', 'w', 'my-tasks'])).toBeNull()
  })

  it('represa a chave que intersecta uma mutação EM VOO', () => {
    const gate = new InvalidationGate(clientWithPending([['ws', 'w', 'robot', 'r']]))
    expect(gate.isDammed(['ws', 'w', 'robot', 'r'])).toBe(true)
    expect(gate.isDammed(['ws', 'w', 'robot', 'r', 'tasks'])).toBe(true) // filho
    expect(gate.isDammed(['ws', 'w', 'robot', 'r2'])).toBe(false)
    expect(gate.isDammed(['ws', 'w', 'overview'])).toBe(false)
  })

  it('represa também por item pendente na fila offline (D7)', () => {
    const offline: OfflinePendingProbe = { hasPendingFor: (kind, id) => kind === 'robot' && id === 'r' }
    const gate = new InvalidationGate(clientWithPending([]), offline)
    expect(gate.isDammed(['ws', 'w', 'robot', 'r'])).toBe(true)
    expect(gate.isDammed(['ws', 'w', 'robot', 'r2'])).toBe(false)
    expect(gate.isDammed(['ws', 'w', 'overview'])).toBe(false) // sem entidade
  })
})
