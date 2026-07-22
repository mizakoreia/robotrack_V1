import { describe, expect, it } from 'vitest'
import { QueryClient } from '@tanstack/react-query'
import { queryClient } from '../src/lib/queryClient'
import { qk, isValidQueryKey, assertValidQueryKey } from '../src/lib/query/keys'
import { installQueryKeyGuard } from '../src/lib/query/guard'

// app-shell-navigation 1.4 (D9) — os defaults da convenção e o guard de forma de
// key. Falha se alguém subir o staleTime de volta aos 5min do template, se uma
// mutation voltar a retentar, ou se uma key de domínio perder o prefixo ['ws',…].

describe('defaults do QueryClient (D9)', () => {
  const opts = queryClient.getDefaultOptions()

  it('staleTime 30s, gcTime 5min, refetchOnWindowFocus off, query retry 1', () => {
    expect(opts.queries?.staleTime).toBe(1000 * 30)
    expect(opts.queries?.gcTime).toBe(1000 * 60 * 5)
    expect(opts.queries?.refetchOnWindowFocus).toBe(false)
    expect(opts.queries?.retry).toBe(1)
  })

  it('mutation retry é 0 (uma escrita que falha não é reenviada em silêncio)', () => {
    expect(opts.mutations?.retry).toBe(0)
  })
})

describe('factory tipada de keys (D9)', () => {
  it('toda key de domínio começa com ["ws", wsId, …]', () => {
    expect(qk.projects('betim')).toEqual(['ws', 'betim', 'projects'])
    expect(qk.tasks('betim', 'r1')).toEqual(['ws', 'betim', 'robot', 'r1', 'tasks'])
    expect(qk.myTasks('betim')).toEqual(['ws', 'betim', 'my-tasks'])
  })
})

describe('validação de forma de key (D9)', () => {
  it('aceita ["ws", wsId, …] e prefixos não-domínio (meta/workspaces/auth)', () => {
    expect(isValidQueryKey(['ws', 'betim', 'projects'])).toBe(true)
    expect(isValidQueryKey(['meta', 'robotApplications'])).toBe(true)
    expect(isValidQueryKey(['workspaces'])).toBe(true)
  })

  it('rejeita key sem prefixo ws e wsId vazio, nomeando a key ofensora', () => {
    expect(isValidQueryKey(['projects'])).toBe(false)
    expect(isValidQueryKey(['ws', '', 'projects'])).toBe(false)
    expect(() => assertValidQueryKey(['projects'])).toThrow(/\['projects'\]|\["projects"\]|projects/)
  })
})

describe('guard instalado no queryCache (D9)', () => {
  it('lança em teste quando uma key fora da convenção é registrada', () => {
    const client = new QueryClient()
    installQueryKeyGuard(client)
    expect(() =>
      client.getQueryCache().build(client, { queryKey: ['projects'], queryFn: async () => 1 }),
    ).toThrow(/convenção D9/)
    client.clear()
  })

  it('não lança para uma key conforme', () => {
    const client = new QueryClient()
    installQueryKeyGuard(client)
    expect(() =>
      client.getQueryCache().build(client, { queryKey: qk.projects('betim'), queryFn: async () => 1 }),
    ).not.toThrow()
    client.clear()
  })
})
