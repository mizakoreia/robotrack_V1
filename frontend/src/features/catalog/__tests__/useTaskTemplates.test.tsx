import { describe, expect, it, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import {
  useCreateTaskTemplate,
  useUpdateTaskTemplate,
  useDeleteTaskTemplate,
  useSyncTaskTemplates,
  useRobotApplications,
} from '../useTaskTemplates'
import { catalogKeys } from '../../../lib/api/catalogKeys'

// task-catalog 6.4 (§1.4 item 3, §3.9, §2.6) — o contrato do CLIENTE do
// catálogo: a escrita atravessa a rede como `appFilters` (nunca `apps`), as
// mutações invalidam `['ws', wsId, 'taskTemplates']`, e a sincronização invalida
// a lista de TAREFAS do robô — a mesma chave que a tabela do robô lê.
//
// A normalização de `Misto / Geral`/`Todas` → `[]` e a materialização das
// tarefas moram no BACKEND (provadas nas specs de request do G4 e nas de sync do
// G6). Aqui o objeto é o fio do cliente: URL, chave e payload certos.

const WS = 'ws-teste'

vi.mock('../../../store/workspaceStore', () => ({
  useWorkspaceStore: (selector: (s: { currentWorkspaceId: string }) => unknown) =>
    selector({ currentWorkspaceId: WS }),
}))

const api = {
  create: vi.fn(),
  update: vi.fn(),
  destroy: vi.fn(),
  sync: vi.fn(),
  robotApplications: vi.fn(),
}

vi.mock('../../../lib/api/endpoints', async (original) => {
  const real = await original<typeof import('../../../lib/api/endpoints')>()
  return {
    ...real,
    taskTemplatesApi: {
      list: real.taskTemplatesApi.list,
      create: (...a: unknown[]) => api.create(...a),
      update: (...a: unknown[]) => api.update(...a),
      destroy: (...a: unknown[]) => api.destroy(...a),
    },
    hierarchyApi: { ...real.hierarchyApi, syncRobotTaskTemplates: (...a: unknown[]) => api.sync(...a) },
    metaApi: { robotApplications: (...a: unknown[]) => api.robotApplications(...a) },
  }
})

function wrapper(client: QueryClient) {
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

function newClient() {
  return new QueryClient({ defaultOptions: { queries: { retry: false } } })
}

beforeEach(() => {
  Object.values(api).forEach((f) => f.mockReset())
})

describe('escrita do catálogo', () => {
  it('cria enviando appFilters (nunca apps) e invalida a chave do catálogo', async () => {
    const client = newClient()
    const spy = vi.spyOn(client, 'invalidateQueries')
    api.create.mockResolvedValue({ id: 't1', cat: 'D. Processo', desc: 'Calibração de Cola', weight: 1, appFilters: ['Sealing'] })

    const { result } = renderHook(() => useCreateTaskTemplate(), { wrapper: wrapper(client) })
    act(() => {
      result.current.mutate({ cat: 'D. Processo', desc: 'Calibração de Cola', appFilters: ['Sealing'] })
    })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    const payload = api.create.mock.calls[0][0] as Record<string, unknown>
    expect(payload.appFilters).toEqual(['Sealing'])
    expect(payload).not.toHaveProperty('apps')
    expect(spy).toHaveBeenCalledWith({ queryKey: catalogKeys.taskTemplates(WS) })
  })

  it('editar para Misto / Geral envia appFilters: ["Misto / Geral"] (o backend limpa)', async () => {
    const client = newClient()
    api.update.mockResolvedValue({ id: 't1', cat: 'D. Processo', desc: 'Calibração de Cola', weight: 1, appFilters: [] })

    const { result } = renderHook(() => useUpdateTaskTemplate(), { wrapper: wrapper(client) })
    act(() => {
      result.current.mutate({ id: 't1', data: { appFilters: ['Misto / Geral'] } })
    })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.update).toHaveBeenCalledWith('t1', { appFilters: ['Misto / Geral'] })
  })

  it('excluir invalida a chave do catálogo', async () => {
    const client = newClient()
    const spy = vi.spyOn(client, 'invalidateQueries')
    api.destroy.mockResolvedValue(undefined)

    const { result } = renderHook(() => useDeleteTaskTemplate(), { wrapper: wrapper(client) })
    act(() => {
      result.current.mutate('t1')
    })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(spy).toHaveBeenCalledWith({ queryKey: catalogKeys.taskTemplates(WS) })
  })
})

describe('sincronização retroativa (§2.6)', () => {
  it('invalida a lista de tarefas DO ROBÔ, para a tabela refazer o fetch', async () => {
    const client = newClient()
    const spy = vi.spyOn(client, 'invalidateQueries')
    api.sync.mockResolvedValue({ addedCount: 1 })

    const { result } = renderHook(() => useSyncTaskTemplates(), { wrapper: wrapper(client) })
    act(() => {
      result.current.mutate('robo-solda-mig')
    })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.sync).toHaveBeenCalledWith('robo-solda-mig')
    expect(spy).toHaveBeenCalledWith({ queryKey: catalogKeys.robotTasks(WS, 'robo-solda-mig') })
  })
})

describe('metadados de Aplicação (§1.2)', () => {
  it('usa a chave global e devolve a lista do backend, sem lista literal em TS', async () => {
    const client = newClient()
    api.robotApplications.mockResolvedValue([
      'Misto / Geral', 'Solda Ponto', 'Solda MIG', 'Handling', 'Sealing', 'Outros',
    ])

    const { result } = renderHook(() => useRobotApplications(), { wrapper: wrapper(client) })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toHaveLength(6)
    expect(client.getQueryData(catalogKeys.robotApplications())).toEqual(result.current.data)
  })
})
