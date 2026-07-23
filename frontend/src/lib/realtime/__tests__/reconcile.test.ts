import { describe, it, expect } from 'vitest'
import { reconcileKeys } from '../reconcile'

const W = 'w1'
const has = (keys: readonly unknown[][], t: unknown[]) => keys.some((k) => JSON.stringify(k) === JSON.stringify(t))

describe('reconcileKeys (7.4 / D6.5)', () => {
  it('gap → subárvore inteira do workspace', () => {
    expect(reconcileKeys(W, { current_seq: 9, gap: true, entity_kinds: ['robot'] })).toEqual([['ws', W]])
  })

  it('since == current_seq (sem tipos, sem gap) → nada a invalidar', () => {
    expect(reconcileKeys(W, { current_seq: 5, gap: false, entity_kinds: [] })).toEqual([])
  })

  it('queda curta → invalida por tipo tocado (overview + listas endereçáveis)', () => {
    const keys = reconcileKeys(W, { current_seq: 7, gap: false, entity_kinds: ['project', 'task'] })
    expect(has(keys, ['ws', W, 'projects'])).toBe(true)
    expect(has(keys, ['ws', W, 'overview'])).toBe(true)
    expect(has(keys, ['ws', W, 'my-tasks'])).toBe(true)
    // sem duplicar 'overview' (project e task ambos o incluem)
    expect(keys.filter((k) => JSON.stringify(k) === JSON.stringify(['ws', W, 'overview'])).length).toBe(1)
  })

  it('tipo desconhecido cai para a subárvore inteira', () => {
    const keys = reconcileKeys(W, { current_seq: 7, gap: false, entity_kinds: ['gizmo'] })
    expect(has(keys, ['ws', W])).toBe(true)
  })
})
