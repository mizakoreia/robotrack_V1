import { describe, expect, it, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useCreateProject, useReorder } from '../useHierarchy'
import { hierarchyKeys } from '../../../lib/api/hierarchyKeys'
import type { ProjectDTO } from '../../../lib/api/endpoints'

const WS = 'ws-teste'

vi.mock('../../../store/workspaceStore', () => ({
  useWorkspaceStore: (selector: (s: { currentWorkspaceId: string }) => unknown) =>
    selector({ currentWorkspaceId: WS }),
}))

const createProject = vi.fn()
vi.mock('../../../lib/api/endpoints', async (original) => {
  const real = await original<typeof import('../../../lib/api/endpoints')>()
  return {
    ...real,
    hierarchyApi: { ...real.hierarchyApi, createProject: (...args: unknown[]) => createProject(...args) },
  }
})

function projeto(id: string, name: string, position: number): ProjectDTO {
  return {
    id,
    name,
    position,
    lock_version: 0,
    updated_at: '2026-07-21T00:00:00Z',
    updated_by_person_id: null,
    progress: { weighted: 0, done: 0, total: 0 },
    cells: [],
  }
}

function wrapper(client: QueryClient) {
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

describe('useCreateProject (6.4)', () => {
  beforeEach(() => createProject.mockReset())

  it('mostra o card na hora com o id do cliente e NÃO duplica quando a resposta chega', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    const key = hierarchyKeys.projects(WS)
    client.setQueryData(key, [projeto('p-1', 'Existente', 0)])

    const id = 'c0a80101-0000-4000-8000-000000000001'
    createProject.mockResolvedValue(projeto(id, 'Nova', 1))

    const { result } = renderHook(() => useCreateProject(), { wrapper: wrapper(client) })

    act(() => {
      result.current.mutate({ name: 'Nova', id })
    })

    // Otimista: aparece antes da resposta, já com o id definitivo.
    await waitFor(() => {
      expect(client.getQueryData<ProjectDTO[]>(key)).toHaveLength(2)
    })
    expect(client.getQueryData<ProjectDTO[]>(key)?.[1].id).toBe(id)

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(client.getQueryData<ProjectDTO[]>(key)?.filter((p) => p.id === id)).toHaveLength(1)
  })

  // O rollback do create otimista (`onError` restaurando o snapshot) NÃO tem
  // teste aqui: no vitest 1.x + jsdom, a rejeição de uma mutation do React
  // Query é contabilizada como unhandled rejection e reprova o arquivo inteiro,
  // com ou sem `onError` (no hook, no `mutate` e no MutationCache) e com ou sem
  // `mutateAsync`. O MESMO padrão snapshot→restore está coberto de forma
  // determinística pelo caminho de conflito de `useReorder`, abaixo.
  // Revisitar quando `quality-and-accessibility` subir o vitest.
})

describe('useReorder (6.5)', () => {
  it('409 devolve a lista ao estado do servidor, não à ordem otimista rejeitada', async () => {
    const client = new QueryClient()
    const key = hierarchyKeys.projects(WS)
    const itens = [projeto('a', 'A', 0), projeto('b', 'B', 1)]
    client.setQueryData(key, itens)

    const send = vi.fn().mockRejectedValue({
      response: { status: 409, data: { error: 'reorder_conflict', details: { current_ids: ['a', 'b', 'novo'] } } },
    })

    const { result } = renderHook(
      () => useReorder({ items: itens, queryKey: key, scopeId: WS, send }),
      { wrapper: wrapper(client) },
    )

    let resultado
    await act(async () => {
      resultado = await result.current(1, 0)
    })

    expect(resultado).toEqual({ status: 'conflict', currentIds: ['a', 'b', 'novo'] })
    expect(client.getQueryData<ProjectDTO[]>(key)?.map((p) => p.id)).toEqual(['a', 'b'])
  })

  it('sucesso grava a lista final devolvida pelo servidor', async () => {
    const client = new QueryClient()
    const key = hierarchyKeys.projects(WS)
    const itens = [projeto('a', 'A', 0), projeto('b', 'B', 1)]
    client.setQueryData(key, itens)

    const finalDoServidor = [projeto('b', 'B', 0), projeto('a', 'A', 1)]
    const send = vi.fn().mockResolvedValue(finalDoServidor)

    const { result } = renderHook(
      () => useReorder({ items: itens, queryKey: key, scopeId: WS, send }),
      { wrapper: wrapper(client) },
    )

    await act(async () => {
      await result.current(1, 0)
    })

    expect(send).toHaveBeenCalledWith(WS, ['b', 'a'])
    expect(client.getQueryData<ProjectDTO[]>(key)?.map((p) => p.position)).toEqual([0, 1])
  })
})
